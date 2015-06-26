//
//  context.h
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM

#ifndef ConTeXt_context_h
#define ConTeXt_context_h

#include "BBLMInterface.h"
#include "BBLMTextIterator.h"

#define LANGUAGE_CODE 'cTeX'

OSErr scanForFunctions(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);

void calculateRuns(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);

#endif
