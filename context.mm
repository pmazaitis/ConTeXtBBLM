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

static void resolveIncludeFile(bblmResolveIncludeParams& io_params)
{
    NSError *err;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    bool not_found = true;
    
    // Extensions we want to look for
    NSArray *valid_extensions = @[@"tex",
                                  @"mkiv",
                                  @"mkvi"];

    // Get URL and filename
    NSURL *requestor = (__bridge NSURL *)io_params.fInDocumentURL;
    NSString *doc_name = (__bridge NSString *)io_params.fInIncludeFileString;
    
    NSString *doc_dir_string = [[requestor absoluteString] stringByDeletingLastPathComponent];
    
    NSURL *doc_dir = [NSURL URLWithString: doc_dir_string];
    // The explicit argument to the \environment command - may be valid
    NSURL *candidate_name = [doc_dir URLByAppendingPathComponent:doc_name];
    
    // Directories we want to search
    //
    // At the moment, this does upward path searching to /Users
    // Other places we could see this from:
    // * texmf tree
    // * user environment variables
    //
    NSMutableArray *search_paths = [[NSMutableArray alloc] init];
    NSString *curr_dir = doc_dir_string;
    
    while ( [curr_dir isNotEqualTo:@"file:/"] && [curr_dir isNotEqualTo:@"file:/Users"])
    {
        [search_paths addObject: curr_dir];
        curr_dir = [curr_dir stringByDeletingLastPathComponent];
    }
    
    // In each directory...
    for (id curr_path in search_paths)
    {
        NSURL *curr_url = [NSURL URLWithString:curr_path];
        candidate_name = [curr_url URLByAppendingPathComponent:doc_name];
        
        // Test if file exists as is
        if ([candidate_name checkResourceIsReachableAndReturnError:&err] == YES)
        {
            NSString* found_file = [candidate_name path];
            io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: found_file] retain];
            return;
        }
        
        NSURL *candidate;
        
        for (id extension in valid_extensions)
        {
            candidate = [candidate_name URLByAppendingPathExtension:extension];
            
            if ([candidate checkResourceIsReachableAndReturnError:&err] == YES)
            {
                NSString* found_file = [candidate path];
                io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: found_file] retain];
                return;
            }
        }
    }
    
    // TODO: sanity check this: don't clobber files
    if (not_found)
    {
        candidate_name = [doc_dir URLByAppendingPathComponent:doc_name];
        // We couldn't find the file, so create the file in the same dir as the source file
        NSURL *creation_URL = [candidate_name URLByAppendingPathExtension:@"tex"];
        NSString* create_file = [creation_URL path];
        [fileManager createFileAtPath:create_file contents:nil attributes:nil];

        // Send the new file name to be displayed in the menu?
        
        if ([fileManager fileExistsAtPath: create_file]) {
            io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: create_file] retain];
        }
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
            resolveIncludeFile(params.fResolveIncludeParams);
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
