//
//  findSetuptex.m
//  ConTeXt
//
//  Created by Paul Mazaitis on 7/31/15.
//
//

#import "findSetuptex.h"

@implementation findSetuptex

// Initialize Search Method
- (void)initiateSearch
{
    // Create the metadata query instance. The metadataSearch @property is
    // declared as retain
    self.metadataSearch=[[NSMetadataQuery alloc] init];
    
    // Register the notifications for batch and completion updates
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queryDidUpdate:)
                                                 name:NSMetadataQueryDidUpdateNotification
                                               object:_metadataSearch];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(initalGatherComplete:)
                                                 name:NSMetadataQueryDidFinishGatheringNotification
                                               object:_metadataSearch];
    
    // Configure the search predicate to find all images using the
    // public.image UTI
    NSPredicate *searchPredicate;
    searchPredicate=[NSPredicate predicateWithFormat:@"kMDItemFSName == 'setuptex'"];
    [_metadataSearch setPredicate:searchPredicate];
    
    // Set the search scope. In this case it will search the User's home directory
    // and the iCloud documents area
    NSArray *searchScopes;
    searchScopes=[NSArray arrayWithObjects:NSMetadataQueryLocalComputerScope,nil];
    [_metadataSearch setSearchScopes:searchScopes];
    
    // Configure the sorting of the results so it will order the results by the
    // display name
    NSSortDescriptor *sortKeys=[[NSSortDescriptor alloc] initWithKey:(id)kMDItemDisplayName
                                                            ascending:YES];
    [_metadataSearch setSortDescriptors:[NSArray arrayWithObject:sortKeys]];
    
    // Begin the asynchronous query
    [_metadataSearch startQuery];
    
}

// Method invoked when notifications of content batches have been received
- (void)queryDidUpdate:sender;
{
    NSLog(@"A data batch has been received");
}


// Method invoked when the initial query gathering is completed
- (void)initalGatherComplete:sender;
{
    // Stop the query, the single pass is completed.
    [_metadataSearch stopQuery];
    
    // Process the content. In this case the application simply
    // iterates over the content, printing the display name key for
    // each image
    NSUInteger i=0;
    for (i=0; i < [_metadataSearch resultCount]; i++) {
        NSMetadataItem *theResult = [_metadataSearch resultAtIndex:i];
        NSString *displayName = [theResult valueForAttribute:(NSString *)kMDItemDisplayName];
        NSLog(@"result at %lu - %@",i,displayName);
    }
    
    // Remove the notifications to clean up after ourselves.
    // Also release the metadataQuery.
    // When the Query is removed the query results are also lost.
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSMetadataQueryDidUpdateNotification
                                                  object:_metadataSearch];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSMetadataQueryDidFinishGatheringNotification
                                                  object:_metadataSearch];
    self.metadataSearch=nil;
}


@end
