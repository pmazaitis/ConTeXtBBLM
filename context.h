//
//  context.h
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis on 3/25/15.
//
//

#ifndef ConTeXt_context_h
#define ConTeXt_context_h

#include "BBLMInterface.h"
#include "BBLMTextIterator.h"

#define LANGUAGE_CODE 'cTeX'
#define kMaxLineLength	256

OSErr scanForFunctions(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);

void calculateRuns(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);


#endif
