/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#import "DDSymbolAddress.h"

#import <string.h>
#import <mach-o/nlist.h>

void * FindSymbolInImage(const char *symbol, const struct mach_header *image, intptr_t slide)
{
	if ((image == NULL) || (symbol == NULL)) {
		return NULL;
	}

	struct symtab_command *symtab_cmd = NULL;

	if (image->magic == MH_MAGIC_64) {
		struct segment_command_64 *linkedit_segment = NULL;
		struct segment_command_64 *text_segment = NULL;

		struct segment_command_64 *cur_seg_cmd;
		uintptr_t cur = (uintptr_t)image + sizeof(struct mach_header_64);
		for (uint i = 0; i < image->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
			cur_seg_cmd = (struct segment_command_64 *)cur;
			if (cur_seg_cmd->cmd == LC_SEGMENT_64) {
				if (!strcmp(cur_seg_cmd->segname, SEG_TEXT)) {
					text_segment = cur_seg_cmd;
				} else if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
					linkedit_segment = cur_seg_cmd;
				}
			} else if (cur_seg_cmd->cmd == LC_SYMTAB) {
				symtab_cmd = (struct symtab_command *)cur_seg_cmd;
			}
		}

		if (!symtab_cmd || !linkedit_segment || !text_segment) {
			return NULL;
		}

		uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)(linkedit_segment->vmaddr - linkedit_segment->fileoff);
		struct nlist_64 *symtab = (struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
		char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

		struct nlist_64 *sym;
		int index;
		for (index = 0, sym = symtab; index < symtab_cmd->nsyms; index += 1, sym += 1) {
			if (sym->n_un.n_strx != 0 && !strcmp(symbol, strtab + sym->n_un.n_strx)) {
				uint64_t address = slide + sym->n_value;
				if (sym->n_desc & N_ARM_THUMB_DEF) {
					return (void *)(address | 1);
				} else {
					return (void *)(address);
				}
			}
		}
	} else {
		struct segment_command *linkedit_segment = NULL;
		struct segment_command *text_segment = NULL;

		struct segment_command *cur_seg_cmd;
		uintptr_t cur = (uintptr_t)image + sizeof(struct mach_header);
		for (uint i = 0; i < image->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
			cur_seg_cmd = (struct segment_command *)cur;
			if (cur_seg_cmd->cmd == LC_SEGMENT) {
				if (!strcmp(cur_seg_cmd->segname, SEG_TEXT)) {
					text_segment = cur_seg_cmd;
				} else if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
					linkedit_segment = cur_seg_cmd;
				}
			} else if (cur_seg_cmd->cmd == LC_SYMTAB) {
				symtab_cmd = (struct symtab_command *)cur_seg_cmd;
			}
		}

		if (!symtab_cmd || !linkedit_segment || !text_segment) {
			return NULL;
		}

		uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)(linkedit_segment->vmaddr - linkedit_segment->fileoff);
		struct nlist *symtab = (struct nlist *)(linkedit_base + symtab_cmd->symoff);
		char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

		struct nlist *sym;
		int index;
		for (index = 0, sym = symtab; index < symtab_cmd->nsyms; index += 1, sym += 1) {
			if (sym->n_un.n_strx != 0 && !strcmp(symbol, strtab + sym->n_un.n_strx)) {
				uint64_t address = slide + sym->n_value;
                if (sym->n_desc & N_ARM_THUMB_DEF) {
					return (void *)(address | 1);
				} else {
					return (void *)(address);
				}
			}
		}
	}

	return NULL;
}
