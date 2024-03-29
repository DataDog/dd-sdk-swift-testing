/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#ifndef DDSymbolAddress_h
#define DDSymbolAddress_h

#import <stdio.h>
#import <mach-o/dyld.h>

void *_Nullable FindSymbolInImage(const char *_Nonnull symbol, const struct mach_header *_Nonnull image, intptr_t slide);

void Profile_reset_counters(void * _Nonnull beginCounters, void *_Nonnull endCounters, void * _Nonnull beginData, void * _Nonnull endData);

#endif /* DDSymbolAddress_h */
