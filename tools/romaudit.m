// Audits a directory of MAME ROM sets against the MAME version built into
// mamearcade_headless.dylib, using the same checks MAMEGameCore performs in
// loadFileAtPath:error: (driver lookup, unsupported machines, ROM audit).

#import <Foundation/Foundation.h>
#import "osd.h"

static BOOL driverIsNotWorking(GameDriverOptions o)
{
    return (o & GameDriverMachineNotWorking) == GameDriverMachineNotWorking ||
           (o & GameDriverMachineIsSkeleton) == GameDriverMachineIsSkeleton;
}

static NSString *problemForRecord(AuditRecord *rec)
{
    switch (rec.substatus)
    {
        case AuditSubstatusFoundBadChecksum:
            return [NSString stringWithFormat:@"wrong checksum (expected %@, found %@)", rec.expectedHashes, rec.actualHashes];
        case AuditSubstatusFoundWrongLength:
            return [NSString stringWithFormat:@"wrong size (expected %lu bytes, found %lu)",
                    (unsigned long)rec.expectedLength, (unsigned long)rec.actualLength];
        case AuditSubstatusNotFound:
            return [NSString stringWithFormat:@"missing (%@)", rec.expectedHashes];
        default:
            return nil; // good, nodump, optional, unverified: acceptable per MAMEGameCore
    }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        if (argc < 2)
        {
            fprintf(stderr, "usage: %s <rom-dir>\n", argv[0]);
            return 2;
        }

        NSString *romDir = [@(argv[1]) stringByStandardizingPath];
        NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:@"romaudit"];
        [NSFileManager.defaultManager createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:nil];

        OSD *osd = [OSD shared];
        [osd.options setBasePath:scratch];
        osd.options.romsPath = romDir;

        NSArray<NSString *> *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:romDir error:nil]
                                      sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSUInteger ok = 0, bad = 0, support = 0;

        for (NSString *file in files)
        {
            NSString *ext = file.pathExtension.lowercaseString;
            if (![ext isEqualToString:@"zip"] && ![ext isEqualToString:@"7z"])
                continue;

            NSString *name = file.stringByDeletingPathExtension;
            NSMutableArray<NSString *> *problems = [NSMutableArray new];
            NSString *title = name;

            AuditResult *ar = nil;
            NSError *err = nil;
            if (![osd setDriver:name withAuditResult:&ar error:&err])
            {
                if ([name rangeOfString:@" "].location == NSNotFound)
                {
                    // not a game: most likely a device/BIOS set (qsound_hle, cchip, …) that games load from
                    support++;
                    printf("--   %s (not a game: BIOS/device support set, fine if other sets use it)\n", name.UTF8String);
                    continue;
                }
                [problems addObject:@"not a MAME driver name: the file must be called exactly <driver>.zip, without suffixes such as \" (1)\""];
            }
            else
            {
                GameDriver *drv = osd.driver;
                title = [NSString stringWithFormat:@"%@ — %@", name, drv.fullName];
                if (drv.parent.length && ![drv.parent isEqualToString:@"0"])
                    title = [title stringByAppendingFormat:@" [clone of %@]", drv.parent];

                if (drv.flags & (GameDriverMachineRequiresArtwork | GameDriverMachineMechanical))
                    [problems addObject:@"mechanical machine, or one that needs artwork: not supported by the core"];
                else if (driverIsNotWorking(drv.flags))
                    [problems addObject:@"driver marked \"not working\" in MAME: the core refuses it"];

                if (ar.summary == AuditSummaryIncorrect || ar.summary == AuditSummaryNotFound)
                {
                    for (AuditRecord *rec in ar.records)
                    {
                        NSString *p = problemForRecord(rec);
                        if (!p)
                            continue;
                        NSString *where = rec.sharedDevice
                            ? [NSString stringWithFormat:@" → belongs in %@.zip (%@)", rec.sharedDevice.shortName, rec.sharedDevice.name]
                            : @"";
                        [problems addObject:[NSString stringWithFormat:@"%@: %@%@", rec.name, p, where]];
                    }
                    if (problems.count == 0)
                        [problems addObject:@"audit failed (set not found)"];
                }
            }

            if (problems.count == 0)
            {
                ok++;
                printf("OK   %s\n", title.UTF8String);
            }
            else
            {
                bad++;
                printf("KO   %s\n", title.UTF8String);
                for (NSString *p in problems)
                    printf("       - %s\n", p.UTF8String);
            }
        }

        printf("\n%lu sets OK, %lu with problems, %lu support sets\n", (unsigned long)ok, (unsigned long)bad, (unsigned long)support);
        return bad ? 1 : 0;
    }
}
