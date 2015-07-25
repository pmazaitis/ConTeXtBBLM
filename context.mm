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
//
//#import <Cocoa/Cocoa.h>


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
    bool candidate_found = false;
    
    // Extensions we want to look for
    NSArray *valid_extensions = @[@"tex",
                                  @"mkiv",
                                  @"mkvi"];

    // Get URL and filename
    //
    // requestor:           full URL of the file requesting the include
    // fileName:            string of the (likely truncated) file name from the include directive
    // fileFullPath:        string of full path to file for creation if we can't find it
    // parentURL:           parent URL of requestor to initiate search
    //
    NSURL *requestor = (__bridge NSURL *)io_params.fInDocumentURL;
    NSString *fileName = (__bridge NSString *)io_params.fInIncludeFileString;
    NSString *fileFullPath = [[NSString alloc] initWithString:[[[requestor  URLByDeletingLastPathComponent] URLByAppendingPathComponent:fileName] path]];
    NSURL *parentURL = [[requestor
                          URLByDeletingLastPathComponent]
                         URLByDeletingLastPathComponent
                         ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *fileEnumerator = [fileManager enumeratorAtURL:parentURL
                                             includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                            options:NSDirectoryEnumerationSkipsHiddenFiles
                                            errorHandler:^BOOL(NSURL *url, NSError *error)
    {
        if (error) {
            NSLog(@"[Error] %@ (%@)", error, url);
            return NO;
        }
        
        return YES;
    }];
    
    for (NSURL *currURL in fileEnumerator)
    {
        // Loop through the items in the iterator; for each item that is a directory,
        // check if any candidates (filename + a valid extension) exist.
        NSNumber *isDirectory;
        [currURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        // Only check if we have a directory
        if ([isDirectory isEqualToNumber:@1])
        {
            NSString *currFilePath = [currURL absoluteString];
            for (id extension in valid_extensions)
            {
                NSString *candidate = [NSString stringWithFormat:@"%@%@.%@",currFilePath,fileName,extension];
                NSURL *candidateURL = [NSURL URLWithString:candidate];
                if ([candidateURL checkResourceIsReachableAndReturnError:&err] == YES)
                {
                    candidate_found = YES;
                    io_params.fOutIncludedItemURL = (CFURLRef) [candidateURL retain];
                    return;
                }
            }
        }
        if (candidate_found) {break;}
    }
    
    // Messing about with UI
//    NSAlert *alert = [[NSAlert alloc] init];
//    [alert addButtonWithTitle:@"Create File"];
//    [alert addButtonWithTitle:@"Cancel"];
//    [alert setMessageText:@"Do you want to create the file?"];
//    [alert setInformativeText:@"BBEdit was unable to locate the referenced file."];
//    [alert setAlertStyle:NSWarningAlertStyle];
    
    
    
    // We couldn't find the file, so create the file in the same dir as the source file
    if (!candidate_found)
    {
        
        NSString *candidate;
        bool has_valid_extension = false;
        
        for (id extension in valid_extensions)
        {
            if ([[fileFullPath pathExtension] isEqualToString:extension])
            {
                has_valid_extension = true;
            }
        }
        
        if (has_valid_extension)
        {
            candidate = fileFullPath;
        }
        else
        {
            candidate = [NSString stringWithFormat:@"%@.tex", fileFullPath];
        }
        
        // Don't clobber existing files
        if (![fileManager fileExistsAtPath: candidate])
        {
            [fileManager createFileAtPath:candidate contents:nil attributes:nil];
        }
        
        // Send the new file name to be displayed in the menu
        
        if ([fileManager fileExistsAtPath: candidate])
        {
            io_params.fOutIncludedItemURL = (CFURLRef) [[NSURL fileURLWithPath: candidate] retain];
        }
        
    }
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
