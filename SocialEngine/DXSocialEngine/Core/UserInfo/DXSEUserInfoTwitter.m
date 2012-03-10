//
//  DXSEUserInfoTwitter.m
//  SocialEngine
//
//  Created by Malaar on 09.03.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "DXSEUserInfoTwitter.h"

@implementation DXSEUserInfoTwitter

@synthesize ID, name, screenName;

//==============================================================================
+ (id) userInfoTwitter
{
    return [[[DXSEUserInfoTwitter alloc] init] autorelease];
}

//==============================================================================
- (void) dealloc
{
    [ID release];
    [name release];
    [screenName release];
    
    [super dealloc];
}

//==============================================================================
- (NSString*) description
{
    return [NSString stringWithFormat:@"id=%@; name=%@; screenName=%@;",
            ID, name, screenName];
}

@end