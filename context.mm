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

#include "AppKit/AppKit.h"

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
    for (id match in global_command_array)
    {
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
    
    while (params.fAdjustRangeParams.fStartIndex > 0)
    {
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
        if (iter.stricmp("\\starttext") == 0 || iter.stricmp("\\startcomponent") || iter.stricmp("\\startproduct"))
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

#pragma mark - Include File Handling

static NSURL* findIncludeFile(bblmResolveIncludeParams& io_params, NSURL* rootDir, NSString* fileName)
{
    NSArray *valid_extensions = @[@"tex",
                                  @"mkiv",
                                  @"mkvi"];
    bool candidate_found = false;
    NSURL* returnURL = nil;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *fileEnumerator = [fileManager enumeratorAtURL:rootDir
                                              includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                            errorHandler:^BOOL(NSURL *url, NSError *error)
                                             {
                                                 if (error)
                                                 {
                                                     NSLog(@"[Error] %@ (%@)", error, url);
                                                     return NO;
                                                 }
                                                 
                                                 return YES;
                                             }];

    // Look for requested file in parent directory and below

    for (NSURL *currURL in fileEnumerator)
    {
        // Loop through the items in the iterator; for each item that is a directory,
        // check if any candidates (filename + a valid extension) exist.
        NSNumber *isDirectory;
        [currURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        // Only check files
        if ([isDirectory isEqualToNumber:@0])
        {
            NSString *currFilePath = [[currURL URLByDeletingLastPathComponent] absoluteString];
            NSString *currFile = [currURL absoluteString];
            //NSLog(@"### Checking for Match with %@",currFilePath);
            for (id extension in valid_extensions)
            {
                NSString *candidate = [NSString stringWithFormat:@"%@%@.%@",currFilePath,fileName,extension];
                NSURL *candidateURL = [NSURL URLWithString:candidate];
                if ([candidate isEqualTo:currFile])
                {
                    candidate_found = true;
                    returnURL = candidateURL;
                }
            }
        }
        if (candidate_found) {break;}
    }
    return returnURL;
}

static NSURL* getTexMfPathUrl ()
{
    // First:   Ask spotlight for the location of kpsewhich, and use that to generate
    //          the value for $TEXMFHOME
    // Second:  Test if ~/texmf is available (and assuming that if it exists, it's valid);
    //          if available, return that path
    // Last:    Give up and return nil

    NSURL * texmfPathUrl = nil;
    
    // get value from plist TODO: next up
//    if (texmfPathUrl == nil)
//    {
//        NSArray * settingsArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"com.mazaitis.bblm"];
//        NSDictionary * settingsDict = [settingsArray objectAtIndex:0];
//        NSString * candidate = [settingsDict valueForKey:@"TEXMFHOME"];
//        NSLog(@"### Got candidate %@", candidate);
//    }

    
    
    
    
    // Try checking spotlight for kpsewhich
    if (texmfPathUrl == nil)
    {
        NSMetadataQuery * q = [[NSMetadataQuery alloc] init];
        [q setPredicate:[NSPredicate predicateWithFormat:@"kMDItemFSName == 'kpsewhich'"]];
        [q startQuery];
        while ([q isGathering])
        {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        [q stopQuery];
        
        NSUInteger i=0;
        NSString * kpsewhichPath = nil;
        for (i=0; i < [q resultCount]; i++)
        {
            NSMetadataItem *theResult = [q resultAtIndex:i];
            NSString *candidate = [theResult valueForAttribute:(NSString *)kMDItemPath];
            //NSLog(@"result at %lu - %@",i,candidate);
            if ([candidate rangeOfString:@"texlive"].location == NSNotFound)
            {
                kpsewhichPath = candidate;
            }
        }
        
        // Now, if we have a path to kpsewhich, fetch the path
        if (kpsewhichPath != nil)
        {
            // Set up an NSTask to run kpsewhich
            NSTask *pathTask = [[NSTask alloc] init];

            [pathTask setLaunchPath:kpsewhichPath];
            [pathTask setArguments:[NSArray arrayWithObjects:@"--expand-var=$TEXMFHOME",nil]];
            
            NSPipe *outputPipe = [NSPipe pipe];
            [pathTask setStandardOutput:outputPipe];
            
            [pathTask launch];
            [pathTask waitUntilExit];
            [pathTask release];
            
            NSFileHandle * read = [outputPipe fileHandleForReading];
            NSData * dataRead = [read readDataToEndOfFile];
            NSString * texmfpath = [[[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
            texmfPathUrl  = [NSURL URLWithString:[@"file://" stringByAppendingString:texmfpath]];
        }
        
    }
    
    // We assume that any errors above will not write garbage to the URL variable
    if (texmfPathUrl == nil)
    {
        NSString * defaultHome = [@"~/texmf/" stringByExpandingTildeInPath];
        BOOL isDir = NO;
        BOOL isFile = [[NSFileManager defaultManager] fileExistsAtPath:defaultHome isDirectory:&isDir];
        if(isFile && isDir)
        {
            texmfPathUrl = [NSURL URLWithString:[@"file://" stringByAppendingString:defaultHome]];
        }
    }
    
    return texmfPathUrl;
}

static void resolveIncludeFile(bblmResolveIncludeParams& io_params)
{
    // This is nil until it gets a proper value
    NSURL * foundURL = nil;
    
    // Get URL and filename
    //
    // requestor:           full URL of the file requesting the include
    // fileName:            string of the (likely truncated) file name from the include directive
    // parentURL:           parent URL of requestor to initiate search
    //
    NSURL *requestor = (__bridge NSURL *)io_params.fInDocumentURL;
    NSString *fileName = (__bridge NSString *)io_params.fInIncludeFileString;
    NSURL *parentURL = [[requestor URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    
    if (foundURL == nil)
    {
        foundURL = findIncludeFile(io_params, parentURL, fileName);
    }
    
    // Query the user's environment for TEXMFHOME
    NSURL * TexMfPathUrl = getTexMfPathUrl();
    
    if (foundURL == nil && TexMfPathUrl != nil)
    {
        foundURL = findIncludeFile(io_params, TexMfPathUrl, fileName);
    }
    
    // We couldn't find the file...
    if (foundURL == nil)
    {
        // ...so see if we want to create it
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        NSString *msg = [NSString stringWithFormat:@"Do you want to create the file %@.tex?",fileName];
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Create File"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setMessageText:msg];
        [alert setInformativeText:@"BBEdit was unable to locate the referenced file."];
        [alert setAlertStyle:NSWarningAlertStyle];
        NSInteger button = [alert runModal];
        
        if (button == NSAlertFirstButtonReturn)
        {
            NSString* fileNameExt = [NSString stringWithFormat:@"%@.tex",fileName];
            // Create file
            // Set the default name for the file and show the panel.
            NSSavePanel* panel = [NSSavePanel savePanel];
            [panel setNameFieldStringValue:fileNameExt];
            button = [panel runModal];
            if (button == NSModalResponseOK) {
                // Got it, use the panel.URL field for something
                [fileManager createFileAtPath:[[panel URL] absoluteString] contents:nil attributes:nil];
                io_params.fOutIncludedItemURL = (CFURLRef) [[panel URL] retain];
            }
        }
        [alert release];
    }
    else
    {
        // We did find the file; let BBEdit know
        io_params.fOutIncludedItemURL = (CFURLRef) [foundURL retain];
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
