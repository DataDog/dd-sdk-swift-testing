#ifndef CSCoverageUtils_h
#define CSCoverageUtils_h

#import <stdio.h>
#import <mach-o/dyld.h>

void *_Nullable FindSymbolInImage(const char *_Nonnull symbol, const struct mach_header *_Nonnull image, intptr_t slide);

#endif /* CSCoverageUtils_h */
