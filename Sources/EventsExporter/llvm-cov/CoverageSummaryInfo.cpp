/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageSummaryInfo.cpp
 *  Derived from:
 *
 *  CoverageSummaryInfo.cpp
 *  LLVM
 */

#include "CoverageSummaryInfo.h"

using namespace llvm;
using namespace coverage;

FunctionCoverageSummary
FunctionCoverageSummary::get(const CoverageMapping &CM,
                             const coverage::FunctionRecord &Function) {
	// Compute the region coverage.
	size_t NumCodeRegions = 0, CoveredRegions = 0;
	for (auto &CR : Function.CountedRegions) {
		if (CR.Kind != CounterMappingRegion::CodeRegion)
			continue;
		++NumCodeRegions;
		if (CR.ExecutionCount != 0)
			++CoveredRegions;
	}

	// Compute the line coverage
	size_t NumLines = 0, CoveredLines = 0;
	CoverageData CD = CM.getCoverageForFunction(Function);
	for (const auto &LCS : getLineCoverageStats(CD)) {
		if (!LCS.isMapped())
			continue;
		++NumLines;
		if (LCS.getExecutionCount())
			++CoveredLines;
	}

	return FunctionCoverageSummary(
		Function.Name, Function.ExecutionCount,
		RegionCoverageInfo(CoveredRegions, NumCodeRegions));
}

FunctionCoverageSummary
FunctionCoverageSummary::get(const InstantiationGroup &Group,
                             ArrayRef<FunctionCoverageSummary> Summaries) {
	std::string Name;
	if (Group.hasName()) {
		Name = std::string(Group.getName());
	} else {
		llvm::raw_string_ostream OS(Name);
		OS << "Definition at line " << Group.getLine() << ", column "
		   << Group.getColumn();
	}

	FunctionCoverageSummary Summary(Name);
	Summary.ExecutionCount = Group.getTotalExecutionCount();
	Summary.RegionCoverage = Summaries[0].RegionCoverage;
	for (const auto &FCS : Summaries.drop_front()) {
		Summary.RegionCoverage.merge(FCS.RegionCoverage);
	}
	return Summary;
}
