/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageExporterJson.h
 *  Derived from:
 *
 *  CoverageExporterJson.h
 *  LLVM
 */

#ifndef LLVM_COV_COVERAGEEXPORTERJSON_H
#define LLVM_COV_COVERAGEEXPORTERJSON_H

#include "CoverageExporter.h"

namespace llvm {

class CoverageExporterJson : public CoverageExporter {
public:
CoverageExporterJson(const coverage::CoverageMapping &CoverageMapping, raw_ostream &OS)
	: CoverageExporter(CoverageMapping, OS) {
}

/// Render the CoverageMapping object.
void renderRoot() override;

/// Render the CoverageMapping object for specified source files.
void renderRoot(ArrayRef<std::string> SourceFiles) override;
};

} // end namespace llvm

#endif // LLVM_COV_COVERAGEEXPORTERJSON_H
