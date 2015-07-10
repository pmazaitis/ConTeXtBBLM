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

#pragma mark - Globals

NSMutableArray* global_command_array = [[NSMutableArray alloc] init];

#pragma mark - Setup and Teardown

// Set up global data structures
static OSErr initData()
{
    OSErr result = noErr;
    NSArray *command_array = [[NSArray alloc] init];
    
    //
    NSBundle* my_bundle = [NSBundle bundleWithIdentifier:@"org.mazaitis.bblm.context"];
    if (my_bundle != nil)
    {
        NSString* file_path = [my_bundle pathForResource:@"context-commands-en" ofType:@"txt"];
        NSCharacterSet *newline_char_set = [NSCharacterSet newlineCharacterSet];
        NSString* file_contents = [NSString stringWithContentsOfFile:file_path
                                                            encoding:NSUTF8StringEncoding
                                                               error:nil];
        command_array = [file_contents componentsSeparatedByCharactersInSet:newline_char_set];
    }

    for (id command in command_array)
    {
        if ([command isNotEqualTo: @""])
        {
            [global_command_array addObject: command];
        }
    }
    return (result);
}




// Clean up global data structures
static void disposeData()
{
    [global_command_array release];
    global_command_array = nil;
}




#pragma mark - Completion

static void AddSymbols(NSString* inPartial, NSMutableArray* inCompletionArray)
{
    for (id match in global_command_array) {
        if ([match hasPrefix: inPartial])
        {
            NSDictionary* the_completion_dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                 @"com.barebones.bblm.function",
                                                 kBBLMCompletionSymbolType,
                                                 match,
                                                 kBBLMSymbolCompletionDisplayString,
                                                 match,
                                                 kBBLMSymbolCompletionText,
                                                 nil];
            [inCompletionArray addObject: the_completion_dict];
            [the_completion_dict release];
        }
    }
}

static void createTextCompletionArray(BBLMParamBlock &params)
{
    bblmCreateCompletionArrayParams	&completionParams = params.fCreateCompletionArrayParams;
    if ([kBBLMCodeRunKind isEqualToString: completionParams.fInCompletionRangeStartRun.runKind]  ||
        [kBBLMCommandRunKind isEqualToString: completionParams.fInCompletionRangeStartRun.runKind]||
        [kBBLMParameterRunKind isEqualToString: completionParams.fInCompletionRangeStartRun.runKind])
    {
        //	no change
        NSMutableArray* completionArray = [[NSMutableArray alloc] init];

        AddSymbols((NSString*) completionParams.fInPartialSymbol, completionArray);
        
        completionParams.fOutSymbolCompletionArray = (CFArrayRef) completionArray;
        completionParams.fOutPreferredCompletionIndex = 0;
    }
    else
    {
        completionParams.fOutAdditionalLookupFlags &= (~ kBBLMSymbolLookupWordsInSystemDict);
    }
}

static void	adjustRangeForTextCompletion(BBLMParamBlock &params)
{
    bblmAdjustCompletionRangeParams	&completionParams = params.fAdjustCompletionRangeParams;
    
    //	never complete against an empty range
    if (0 == completionParams.fInProposedCompletionRange.length)
        completionParams.fOutAdjustedCompletionRange = CFRangeMake(kCFNotFound, 0);
    else
        completionParams.fOutAdjustedCompletionRange = completionParams.fInProposedCompletionRange;
}


#pragma mark - Utility Functions

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
    NSURL *candidate_name;
    
    // Directories we want to search
    //
    // At the moment, this does upward path searching to /Users (or /)
    // Other places we could seed this from:
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
    
    // We couldn't find the file, so create the file in the same dir as the source file
    if (not_found)
    {
        candidate_name = [doc_dir URLByAppendingPathComponent:doc_name];
        
        // (We should never need this test, but: being safe, here)
        if ([candidate_name checkResourceIsReachableAndReturnError:&err] == NO )
        {
            NSURL *creation_URL = [candidate_name URLByAppendingPathExtension:@"tex"];
            NSString* create_file = [creation_URL path];
            [fileManager createFileAtPath:create_file contents:nil attributes:nil];

            // Send the new file name to be displayed in the menu
            
            if ([fileManager fileExistsAtPath: create_file]) {
                io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: create_file] retain];
            }
        }
    }
    [search_paths release];
    search_paths = nil;
}

#pragma mark - Entry Point

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
        {
            result = initData();
            break;
        }
		case kBBLMDisposeMessage:
		{
            disposeData();
            result = noErr;
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
		case kBBLMEscapeStringMessage:
		{
			result = userCanceledErr;
			break;
		}
        case kBBLMFilterRunForTextCompletion:
        {
            break;
        }
            
        case kBBLMSetCategoriesMessage:
        case kBBLMSetCategoriesForTextCompletionMessage:
        {
            SInt8*	cat = params.fCategoryParams.fCategoryTable;
            
            cat[(unsigned char)'\\'] = '<';
            break;
        }
        case kBBLMAdjustRangeForTextCompletion:
        {
            adjustRangeForTextCompletion(params);
            break;
        }
        case kBBLMCreateTextCompletionArray:
        {
            createTextCompletionArray(params);
            result = noErr;
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
