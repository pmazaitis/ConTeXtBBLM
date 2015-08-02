//
//  findSetuptex.h
//  ConTeXt
//
//  Created by Paul Mazaitis on 7/31/15.
//
//

#import <Foundation/Foundation.h>

@interface findSetuptex : NSObject

- (void)initiateSearch;

- (void)queryDidUpdate:sender;

- (void)initalGatherComplete:sender;

@property (nonatomic, strong, retain) NSMetadataQuery *metadataSearch;

@end
