//
//  DXSELinkedIn.h
//  SocialEngine
//
//  Created by Maxim Letushov on 9/21/12.
//
//

#import <Foundation/Foundation.h>
#import "DXSEModule.h"

static NSString *const cLoginSuccessTypeKey = @"LoginSuccessTypeKey";

typedef enum {
    LinkedInLoginSuccessTypeLogined,
    LinkedInLoginSuccessTypeCanceled
} LinkedInLoginSuccessType;

static NSInteger const cLinkedInScopeDefault = 0;
static NSInteger const cLinkedInScopeFullProfile = 1;
static NSInteger const cLinkedInScopeEmail = 2;

typedef long LINKEDIN_PROFILE_FIELDS;
typedef NSInteger LinkedInScope;

@interface DXSELinkedIn : DXSEModule

// property profileFields
//      need set before call getUserInfo
//      default value LINKEDIN_PROFILE_FIELDS__ALL
@property (nonatomic, assign) LINKEDIN_PROFILE_FIELDS profileFields;
@property (nonatomic, assign) LinkedInScope scope;

@end
