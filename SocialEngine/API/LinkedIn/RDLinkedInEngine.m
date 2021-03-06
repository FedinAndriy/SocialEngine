//
//  RDLinkedInEngine.m
//  LinkedInClientLibrary
//
//  Created by Sixten Otto on 12/30/09.
//  Copyright 2010 Results Direct. All rights reserved.
//

#import "RD_OAuthConsumer/RD_OAuthConsumer.h"

#import "RDLinkedInEngine.h"
#import "RDLinkedInHTTPURLConnection.h"
#import "RDLinkedInRequestBuilder.h"
#import "RDLinkedInResponseParser.h"
#import "RDLogging.h"

static NSString *const kAPIBaseURL           = @"http://api.linkedin.com";
static NSString *const kOAuthRequestTokenURL = @"https://api.linkedin.com/uas/oauth/requestToken";
static NSString *const kOAuthAccessTokenURL  = @"https://api.linkedin.com/uas/oauth/accessToken";
static NSString *const kOAuthAuthorizeURL    = @"https://www.linkedin.com/uas/oauth/authorize";
static NSString *const kOAuthInvalidateURL   = @"https://api.linkedin.com/uas/oauth/invalidateToken";

static const unsigned char kRDLinkedInDebugLevel = 0;

NSString *const RDLinkedInEngineRequestTokenNotification = @"RDLinkedInEngineRequestTokenNotification";
NSString *const RDLinkedInEngineAccessTokenNotification  = @"RDLinkedInEngineAccessTokenNotification";
NSString *const RDLinkedInEngineTokenInvalidationNotification  = @"RDLinkedInEngineTokenInvalidationNotification";
NSString *const RDLinkedInEngineAuthFailureNotification  = @"RDLinkedInEngineAuthFailureNotification";
NSString *const RDLinkedInEngineTokenKey                 = @"RDLinkedInEngineTokenKey";

const NSUInteger kRDLinkedInMaxStatusLength = 140;


@interface RDLinkedInEngine ()

- (RDLinkedInConnectionID *)sendAPIRequestWithURL:(NSURL *)url HTTPMethod:(NSString *)method body:(NSData *)body;
- (void)sendTokenRequestWithURL:(NSURL *)url token:(RD_OAToken *)token onSuccess:(SEL)successSel onFail:(SEL)failSel;

@property (nonatomic, strong) NSString *redirectURL;

@end


@implementation RDLinkedInEngine

@synthesize verifier = rdOAuthVerifier;

+ (id)engineWithConsumerKey:(NSString *)consumerKey consumerSecret:(NSString *)consumerSecret redirectURL:(NSString *)redirectURL delegate:(id<RDLinkedInEngineDelegate>)delegate {
    return [[self alloc] initWithConsumerKey:consumerKey consumerSecret:consumerSecret redirectURL:redirectURL delegate:delegate];
}

- (id)initWithConsumerKey:(NSString *)consumerKey consumerSecret:(NSString *)consumerSecret redirectURL:(NSString *)redirectURL delegate:(id<RDLinkedInEngineDelegate>)delegate {
  self = [super init];
  if( self != nil ) {
    rdDelegate = delegate;
    rdOAuthConsumer = [[RD_OAConsumer alloc] initWithKey:consumerKey secret:consumerSecret];
    rdConnections = [[NSMutableDictionary alloc] init];
      _redirectURL = [redirectURL copy];
  }
  return self;
}

- (void)dealloc {
  rdDelegate = nil;
}


#pragma mark connection methods

- (NSUInteger)numberOfConnections {
  return [rdConnections count];
}

- (NSArray *)connectionIdentifiers {
  return [rdConnections allKeys];
}

- (void)closeConnection:(RDLinkedInHTTPURLConnection *)connection {
  if( connection ) {
    [connection cancel];
    [rdConnections removeObjectForKey:connection.identifier];
  }
}

- (void)closeConnectionWithID:(RDLinkedInConnectionID *)identifier {
  [self closeConnection:[rdConnections objectForKey:identifier]];
}

- (void)closeAllConnections {
  [[rdConnections allValues] makeObjectsPerformSelector:@selector(cancel)];
  [rdConnections removeAllObjects];
}


#pragma mark authorization methods

- (BOOL)isAuthorized {
  if( rdOAuthAccessToken.key && rdOAuthAccessToken.secret ) return YES;
  
  // check for cached creds
  if( [rdDelegate respondsToSelector:@selector(linkedInEngineAccessToken:)] ) {
    rdOAuthAccessToken = [rdDelegate linkedInEngineAccessToken:self];
    if( rdOAuthAccessToken.key && rdOAuthAccessToken.secret ) return YES;
  }
  
  // no valid access token found
  rdOAuthAccessToken = nil;
  return NO;
}

- (BOOL)hasRequestToken {
  return (rdOAuthRequestToken.key && rdOAuthRequestToken.secret);
}

- (void)requestRequestToken {
//    NSString *url = [NSString stringWithFormat:@"%@?scope=r_basicprofile", kOAuthRequestTokenURL];
    [self sendTokenRequestWithURL:[NSURL URLWithString:kOAuthRequestTokenURL]
                          token:nil
                      onSuccess:@selector(setRequestTokenFromTicket:data:)
                         onFail:@selector(oauthTicketFailed:data:)];
}

- (void)requestAccessToken {
  [self sendTokenRequestWithURL:[NSURL URLWithString:kOAuthAccessTokenURL]
                          token:rdOAuthRequestToken
                      onSuccess:@selector(setAccessTokenFromTicket:data:)
                         onFail:@selector(oauthTicketFailed:data:)];
}

- (void)requestTokenInvalidation {
  [self sendTokenRequestWithURL:[NSURL URLWithString:kOAuthInvalidateURL]
                          token:rdOAuthRequestToken
                      onSuccess:@selector(tokenInvalidationSucceeded:data:)
                         onFail:@selector(oauthTicketFailed:data:)];
}

- (NSURLRequest *)authorizationFormURLRequest {
  RD_OAMutableURLRequest *request = [[RD_OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kOAuthAuthorizeURL] consumer:nil token:rdOAuthRequestToken realm:nil signatureProvider:nil];
  [request setParameters: [NSArray arrayWithObject: [[RD_OARequestParameter alloc] initWithName:@"oauth_token" value:rdOAuthRequestToken.key]]];
  return request;
}


#pragma mark profile methods

- (RDLinkedInConnectionID *)profileForCurrentUser:(NSString *)profileFieldsSeparatedByComma {
    NSString *urlAppendPart = [NSString stringWithFormat:@"/v1/people/~:(%@)", profileFieldsSeparatedByComma];
    NSURL* url = [NSURL URLWithString:[kAPIBaseURL stringByAppendingString:urlAppendPart]];
    return [self sendAPIRequestWithURL:url HTTPMethod:@"GET" body:nil];
}

- (RDLinkedInConnectionID *)profileForCurrentUser {
  NSURL* url = [NSURL URLWithString:[kAPIBaseURL stringByAppendingString:@"/v1/people/~"]];
  return [self sendAPIRequestWithURL:url HTTPMethod:@"GET" body:nil];
}

- (RDLinkedInConnectionID *)profileForPersonWithID:(NSString *)memberID {
  NSURL* url = [NSURL URLWithString:[kAPIBaseURL stringByAppendingFormat:@"/v1/people/id=%@", [memberID stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
  return [self sendAPIRequestWithURL:url HTTPMethod:@"GET" body:nil];
}

- (RDLinkedInConnectionID *)updateStatus:(NSString *)newStatus {
  NSURL* url = [NSURL URLWithString:[kAPIBaseURL stringByAppendingString:@"/v1/people/~/current-status"]];
  newStatus = [newStatus length] > kRDLinkedInMaxStatusLength ? [newStatus substringToIndex:kRDLinkedInMaxStatusLength] : newStatus;
  NSData* body = [RDLinkedInRequestBuilder buildSimpleRequestWithRootNode:@"current-status" content:newStatus];
  return [self sendAPIRequestWithURL:url HTTPMethod:@"PUT" body:body];
}

- (RDLinkedInConnectionID *)shareUrl:(NSString *)submittedUrl imageUrl:(NSString *)submittedImageUrl title:(NSString*)title comment:(NSString*)comment {
  NSURL* url = [NSURL URLWithString:[kAPIBaseURL stringByAppendingString:@"/v1/people/~/shares"]];

  comment = [comment length] > kRDLinkedInMaxStatusLength ? [comment substringToIndex:kRDLinkedInMaxStatusLength] : comment;

  NSString *xml = [[NSString alloc] initWithFormat:@"			\
				   <share>										\
				   <comment>%@</comment>						\
				   <content>									\
				   <title>%@</title>							\
				   <submitted-url>%@</submitted-url>			\
				   <submitted-image-url>%@</submitted-image-url>\
				   </content>									\
				   <visibility>									\
				   <code>anyone</code>							\
				   </visibility>								\
				   </share>",
				   comment,
				   title,
				   submittedUrl,
				   submittedImageUrl];
	
  // Cleaning the XML content
  xml = [xml stringByReplacingOccurrencesOfString:@"\n" withString:@""];
  xml = [xml stringByReplacingOccurrencesOfString:@"	" withString:@""];
	 
  xml = [[NSString alloc]
		   initWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n%@",xml];
	
  NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
	
  //NSLog(@"xml=%@", xml);
  //NSLog(@"data=%@", data);
	
  return [self sendAPIRequestWithURL:url HTTPMethod:@"POST" body:data];
}

#pragma mark private

- (RDLinkedInConnectionID *)sendAPIRequestWithURL:(NSURL *)url HTTPMethod:(NSString *)method body:(NSData *)body {
  if( !self.isAuthorized ) return nil;
  RDLOG(@"sending API request to %@", url);
  
  // create and configure the URL request
  RD_OAMutableURLRequest* request = [[RD_OAMutableURLRequest alloc] initWithURL:url
                                                                  consumer:rdOAuthConsumer 
                                                                     token:rdOAuthAccessToken 
                                                                     realm:nil
                                                         signatureProvider:nil];
  [request setHTTPShouldHandleCookies:NO];
  [request setValue:@"text/xml;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
  if( method ) {
    [request setHTTPMethod:method];
  }
  
  // prepare the request before setting the body, because OAuthConsumer wants to parse the body
  // for parameters to include in its signature, but LinkedIn doesn't work that way
  [request prepare];
  if( [body length] ) {
    [request setHTTPBody:body];
  }
  
  // initiate a URL connection with this request
  RDLinkedInHTTPURLConnection* connection = [[RDLinkedInHTTPURLConnection alloc] initWithRequest:request delegate:self];
  if( connection ) {
    [rdConnections setObject:connection forKey:connection.identifier];
  }
  
  return connection.identifier;
}

- (void)parseConnectionResponse:(RDLinkedInHTTPURLConnection *)connection {
  NSError* error = nil;
  id results = nil;
  
  if( [RDLinkedInResponseParser parseXML:[connection data] connection:connection results:&results error:&error] ) {
    if( [rdDelegate respondsToSelector:@selector(linkedInEngine:requestSucceeded:withResults:)] ) {
      [rdDelegate linkedInEngine:self requestSucceeded:connection.identifier withResults:results];
    }
  }
  else {
    if( [rdDelegate respondsToSelector:@selector(linkedInEngine:requestFailed:withError:)] ) {
      [rdDelegate linkedInEngine:self requestFailed:connection.identifier withError:error];
    }    
  }
}

- (void)sendTokenRequestWithURL:(NSURL *)url token:(RD_OAToken *)token onSuccess:(SEL)successSel onFail:(SEL)failSel {
  RD_OAMutableURLRequest* request = [[RD_OAMutableURLRequest alloc] initWithURL:url consumer:rdOAuthConsumer token:token realm:nil signatureProvider:nil];
	if( !request ) return;

    [request setHTTPMethod:@"POST"];
    
    NSMutableArray *parametersArray = [NSMutableArray array];
    
    if (self.scopeRequestTokenParam) {
        RD_OARequestParameter *scopeParameter = [RD_OARequestParameter requestParameterWithName:@"scope" value:self.scopeRequestTokenParam];
        [parametersArray addObject:scopeParameter];
    }
    
    if (self.redirectURL) {
        RD_OARequestParameter *redirectURLParameter = [RD_OARequestParameter requestParameterWithName:@"oauth_callback" value:self.redirectURL];
        [parametersArray addObject:redirectURLParameter];
    }
    
    [request setParameters:parametersArray];	

	if( rdOAuthVerifier.length ) token.pin = rdOAuthVerifier;
	
  RD_OADataFetcher* fetcher = [[RD_OADataFetcher alloc] init];
  [fetcher fetchDataWithRequest:request delegate:self didFinishSelector:successSel didFailSelector:failSel];
}

- (void)oauthTicketFailed:(RD_OAServiceTicket *)ticket data:(NSData *)data {
  //RDLOG(@"oauthTicketFailed! %@", ticket);
  
  // notification of authentication failure
  [[NSNotificationCenter defaultCenter]
   postNotificationName:RDLinkedInEngineAuthFailureNotification object:self];
}

- (void)setRequestTokenFromTicket:(RD_OAServiceTicket *)ticket data:(NSData *)data {
  //RDLOG(@"got request token ticket response: %@ (%lu bytes)", ticket, (unsigned long)[data length]);
  if (!ticket.didSucceed || !data) return;
  
  NSString *dataString = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
  if (!dataString) return;
  
  rdOAuthRequestToken = [[RD_OAToken alloc] initWithHTTPResponseBody:dataString];
  //RDLOG(@"  request token set %@", rdOAuthRequestToken.key);
  
  if( rdOAuthVerifier.length ) rdOAuthRequestToken.pin = rdOAuthVerifier;
  
  // notification of request token
  [[NSNotificationCenter defaultCenter]
   postNotificationName:RDLinkedInEngineRequestTokenNotification object:self
   userInfo:[NSDictionary dictionaryWithObject:rdOAuthRequestToken forKey:RDLinkedInEngineTokenKey]];
}

- (void)setAccessTokenFromTicket:(RD_OAServiceTicket *)ticket data:(NSData *)data {
  //RDLOG(@"got access token ticket response: %@ (%lu bytes)", ticket, (unsigned long)[data length]);
  if (!ticket.didSucceed || !data) return;
  
  NSString *dataString = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
  if (!dataString) return;
  
  if( rdOAuthVerifier.length && [dataString rangeOfString:@"oauth_verifier"].location == NSNotFound ) {
    dataString = [dataString stringByAppendingFormat:@"&oauth_verifier=%@", rdOAuthVerifier];
  }
  
  rdOAuthAccessToken = [[RD_OAToken alloc] initWithHTTPResponseBody:dataString];
  //RDLOG(@"  access token set %@", rdOAuthAccessToken.key);
  
  if( [rdDelegate respondsToSelector:@selector(linkedInEngineAccessToken:setAccessToken:)] ) {
    [rdDelegate linkedInEngineAccessToken:self setAccessToken:rdOAuthAccessToken];
  }
  
  // notification of access token
  [[NSNotificationCenter defaultCenter]
   postNotificationName:RDLinkedInEngineAccessTokenNotification object:self
   userInfo:[NSDictionary dictionaryWithObject:rdOAuthAccessToken forKey:RDLinkedInEngineTokenKey]];
}

- (void)tokenInvalidationSucceeded:(RD_OAServiceTicket *)ticket data:(NSData *)data {
  RD_OAToken* invalidToken = rdOAuthAccessToken;
  rdOAuthAccessToken = nil;
  
  NSHTTPCookieStorage* cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
  for( NSHTTPCookie *c in [cookieStorage cookies] ){
    if( [[c domain] hasSuffix:@".linkedin.com"] ) {
      [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
    }
  }
  
  if( [rdDelegate respondsToSelector:@selector(linkedInEngineAccessToken:setAccessToken:)] ) {
    [rdDelegate linkedInEngineAccessToken:self setAccessToken:nil];
  }
  
  // notification of token invalidation
  [[NSNotificationCenter defaultCenter]
   postNotificationName:RDLinkedInEngineTokenInvalidationNotification object:self
   userInfo:[NSDictionary dictionaryWithObject:invalidToken forKey:RDLinkedInEngineTokenKey]];
}


#pragma mark NSURLConnectionDelegate


- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  //RDLOG(@"received credential challenge!");
  [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
}


- (void)connection:(RDLinkedInHTTPURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  // This method is called when the server has determined that it has enough information to create the NSURLResponse.
  // it can be called multiple times, for example in the case of a redirect, so each time we reset the data.
  [connection resetData];
  
  NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
  int statusCode = [resp statusCode];
  
  if( kRDLinkedInDebugLevel > 5 ) {
    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
    RDLOG(@"%@ (%d) [%@]:\r%@",
          connection.request.URL,
          [resp statusCode], 
          [NSHTTPURLResponse localizedStringForStatusCode:[resp statusCode]], 
          [resp allHeaderFields]);
  }
  
  if( statusCode >= 400 ) {
    // error response; just abort now
    NSError *error = [NSError errorWithDomain:@"HTTP" code:statusCode
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                               [resp allHeaderFields], @"headers",
                                               nil]];
    if( [rdDelegate respondsToSelector:@selector(linkedInEngine:requestFailed:withError:)] ) {
      [rdDelegate linkedInEngine:self requestFailed:connection.identifier withError:error];
    }
    [self closeConnection:connection];
  }
  else if( statusCode == 204 || statusCode == 201) {
    // 204: no content; so skip the parsing, and declare success!
	// 201: created. declare success!
    if( [rdDelegate respondsToSelector:@selector(linkedInEngine:requestSucceeded:withResults:)] ) {
      [rdDelegate linkedInEngine:self requestSucceeded:connection.identifier withResults:nil];
    }
    [self closeConnection:connection];
  }
}


- (void)connection:(RDLinkedInHTTPURLConnection *)connection didReceiveData:(NSData *)data {
  [connection appendData:data];
}


- (void)connection:(RDLinkedInHTTPURLConnection *)connection didFailWithError:(NSError *)error {
  if( [rdDelegate respondsToSelector:@selector(linkedInEngine:requestFailed:withError:)] ) {
    [rdDelegate linkedInEngine:self requestFailed:connection.identifier withError:error];
  }
  
  [self closeConnection:connection];
}


- (void)connectionDidFinishLoading:(RDLinkedInHTTPURLConnection *)connection {
  NSData *receivedData = [connection data];
  if( [receivedData length] ) {
    if( kRDLinkedInDebugLevel > 0 ) {
      NSString *dataString = [NSString stringWithUTF8String:[receivedData bytes]];
      RDLOG(@"Succeeded! Received %d bytes of data:\r\r%@", [receivedData length], dataString);
    }
    
    if( kRDLinkedInDebugLevel > 8 ) {
      // Dump XML to file for debugging.
      NSString *dataString = [NSString stringWithUTF8String:[receivedData bytes]];
      [dataString writeToFile:[@"~/Desktop/linkedin_messages.xml" stringByExpandingTildeInPath] 
                   atomically:NO encoding:NSUnicodeStringEncoding error:NULL];
    }
    
    [self parseConnectionResponse:connection];
  }
  
  // Release the connection.
  [rdConnections removeObjectForKey:[connection identifier]];
}

@end
