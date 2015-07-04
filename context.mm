//
//  context.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM


#include "context.h"
#include <string>

//#include <CoreFoundation/CoreFoundation.h>
//#include <Foundation/Foundation.h>

#pragma mark -

// Roll back to the start of the more recent text run

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

// Try to guess if this is a ConTeXt file; look for a \starttext command.

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

// Is the current run spellable?
//
// We only consider set text and commments to be spellable, in the following run kinds:
//
// * kBBLMCodeRunKind
// * kBBLMCommentRunKind

static void isRunSpellable(BBLMParamBlock &params)
{
    NSString * curr_kind = params.fCanSpellCheckRunParams.fRunKind;
    
    if ([curr_kind isEqualToString:kBBLMCodeRunKind] || [curr_kind isEqualToString:kBBLMCommentRunKind])
    {
        params.fCanSpellCheckRunParams.fRunCanBeSpellChecked = true;
    }
    else
    {
        params.fCanSpellCheckRunParams.fRunCanBeSpellChecked = false;
    }
}

// Completion

static void createTextCompletionArray(bblmCreateCompletionArrayParams &io_params)
{
    
}

// See if there's a new SDK with the new URL-style interface?

static void createResolveIncludeFile(bblmResolveIncludeParams& io_params)
{
    NSError *err;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    // Extensions we want to look for
    NSArray *valid_extensions = @[@"tex", @"mkiv", @"mkvi"];
    //NSMutableArray *search_paths;
    
    //bool success;
    
    // fInDocumentURL	CFURLRef	@"file:///Users/goob/Proj/BBEditExtensions/NewExamples/ContextTesting/test_doc2.mkiv"	0x06e09f20
    // fInIncludeFileString	CFStringRef	@"test_env"	0x06ecc380
    //

    //
    //NSURL *requested_file = [NSURL fileURLWithPath: (NSString *)io_params.fInDocumentURL];
    //NSString *urlString = (NSString *)io_params.fInDocumentURL;

    
    // Get URL and filename
    NSURL *requestor = (__bridge NSURL *)io_params.fInDocumentURL;
    NSLog(@"### Asking File: %@", requestor);
    NSString *file_name = (__bridge NSString *)io_params.fInIncludeFileString;
    NSLog(@"### Got request: %@", file_name);
    
    NSString *base_url_string = [[requestor absoluteString] stringByDeletingLastPathComponent];
    
    NSURL *base_url = [NSURL URLWithString: base_url_string];
    
    //NSURL *candidate = [NSURL URLWithString:file_name relativeToURL:base_url];
    NSURL *candidate_name = [base_url URLByAppendingPathComponent:file_name];
    
    
    // Test if file exists as is
    if ([candidate_name checkResourceIsReachableAndReturnError:&err] == YES)
    {
        NSLog(@"### Found: %@", candidate_name);
        return;
    }
    else
    {
        NSLog(@"### Not found: %@", candidate_name);
    }

    NSURL *candidate;
    
    for (id extension in valid_extensions)
    {
        //...do something useful with myArrayElement
        candidate = [candidate_name URLByAppendingPathExtension:extension];
        if ([candidate checkResourceIsReachableAndReturnError:&err] == YES)
        {
            NSLog(@"### Found: %@", candidate);
            return;
        }
        else
        {
            NSLog(@"### Not found: %@", candidate);
        }
    }
    
 
    
    // We couldn't find the file, so create the file in the same dir as the source file
    NSURL *creation_URL = [candidate URLByAppendingPathExtension:@"tex"];
    NSLog(@"### Could not find file. Creating file: %@", creation_URL);
    NSString* create_file = [creation_URL path];
    [[NSFileManager defaultManager] createFileAtPath:create_file contents:nil attributes:nil];

    
    // Send the new file name to be displayed in the menu?
    
    if ([fileManager fileExistsAtPath: create_file]) {
        io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: create_file] retain];
    }
    
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
        case kBBLMCanSpellCheckRunMessage:
        {
            isRunSpellable(params);
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
        case kBBLMAdjustRangeForTextCompletion:
        {
            break;
        }
        case kBBLMFilterRunForTextCompletion:
        {
            break;
        }
        case kBBLMCreateTextCompletionArray:
        {
            createTextCompletionArray(params.fCreateCompletionArrayParams);
            result = noErr;
            break;
        }
        case kBBLMSetCategoriesForTextCompletionMessage:
        {
            SInt8*  cat = params.fCategoryParams.fCategoryTable;
            
            cat[92] = 'a'; //(int)'\\'
            break;
        }
        case kBBLMResolveIncludeFileMessage:
        {
            NSLog(@"### BBLM - createResolveIncludeFile");
            createResolveIncludeFile(params.fResolveIncludeParams);
            result = noErr;
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
