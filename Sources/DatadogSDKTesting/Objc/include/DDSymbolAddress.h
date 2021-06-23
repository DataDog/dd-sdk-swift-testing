/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#ifndef DDSymbolAddress_h
#define DDSymbolAddress_h

#import <stdio.h>
#import <mach-o/dyld.h>

void *_Nullable FindSymbolInImage(const char *_Nonnull symbol, const struct mach_header *_Nonnull image, intptr_t slide);

#endif /* DDSymbolAddress_h */
