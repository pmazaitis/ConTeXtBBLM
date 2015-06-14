//
//
//
//  BBedit Language Module for ConTeXt.
//
//
// Documentation!
// Documentation!
// Documentation!
//
// TODO: Documentation!

#include "context.h"

#pragma mark -

static void adjustRange(BBLMParamBlock &params, const BBLMCallbackBlock &callbacks)
{
    bool result;
    
    while (params.fAdjustRangeParams.fStartIndex > 0) {
        DescType language;
        NSString *kind;
        SInt32 pos;
        SInt32 len;
        result = bblmGetRun(&callbacks, params.fAdjustRangeParams.fStartIndex, language, kind, pos, len);
        if (!result)
            return;
        if ([kind isEqualToString:@"kBBLMRunIsCode"])
            return;
        params.fAdjustRangeParams.fStartIndex -= 1;
    }
}


// Try to guess if this is a context file

static void guessIfContext(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks)
{
    int context_guess = kBBLMGuessMaybe;
    BBLMTextIterator iter(params);
    
    while (iter.InBounds())
    {
        if (iter.stricmp("\\starttext") == 0)
        {
            context_guess = kBBLMGuessDefiniteYes;
            break;
        }
        iter++;
    }
    params.fGuessLanguageParams.fGuessResult = context_guess;
}

extern "C"
{

OSErr	ConTeXtMachO(BBLMParamBlock &params, const BBLMCallbackBlock &bblmCallbacks);

OSErr	ConTeXtMachO(BBLMParamBlock &params, const BBLMCallbackBlock &bblmCallbacks)
{
	OSErr	result = noErr;
	
	//
	//	a language module must always make sure that the parameter block
	//	is valid by checking the signature, version number, and size
	//	of the parameter block. Note also that version 2 is the first
	//	usable version of the parameter block; anything older should
	//	be rejected.
	//
	
	//
	//	RMS 010925 the check for params.fVersion > kBBLMParamBlockVersion
	//	is overly strict, since there are no structural changes that would
	//	break backward compatibility; only new members are added.
	//

	if ((params.fSignature != kBBLMParamBlockSignature) ||
		(params.fVersion == 0) ||
		(params.fVersion < 2) ||
		(params.fLength < sizeof(BBLMParamBlock)))
	{
		return paramErr;
	}
	switch (params.fMessage)
	{
		case kBBLMInitMessage:
		case kBBLMDisposeMessage:
		{
			result = noErr;	// nothing to do
			break;
		}
		
        case kBBLMGuessLanguageMessage:
        {
            guessIfContext(params, bblmCallbacks);
            result = noErr;
            break;
        }
            
		case kBBLMScanForFunctionsMessage:
		{
			result = scanForFunctions(params, bblmCallbacks);
            break;
		}
		
		case kBBLMAdjustRangeMessage:
        {
            adjustRange(params, bblmCallbacks);
            result = noErr;
            break;
        }
		case kBBLMCalculateRunsMessage:
        {
            calculateRuns(params, bblmCallbacks);
            result = noErr;
            break;
        }
		case kBBLMAdjustEndMessage:
        {
            //adjustEnd(params, bblmCallbacks);
            result = noErr;
            break;
        }
		case kBBLMSetCategoriesMessage:
        {
            break;
        }
		case kBBLMEscapeStringMessage:
		{
			result = userCanceledErr;
			break;
		}
			
		default:
		{
			result = paramErr;
			break;
		}
	}
	return result;
}
}
