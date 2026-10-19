//
//  WebRequestErrorBridge.mm
//  Reynard
//
//  Created by Minh Ton on 18/10/26.
//

#import "WebRequestErrorBridge.h"

#import "nsError.h"

@implementation WebRequestErrorBridge

+ (NSString *)loadErrorNameForCode:(uint32_t)code
                        errorClass:(NSInteger)errorClass {
    switch (static_cast<nsresult>(code)) {
        case NS_ERROR_PHISHING_URI:
            return @"phishing";
        case NS_ERROR_MALWARE_URI:
            return @"malware";
        case NS_ERROR_UNWANTED_URI:
            return @"unwanted";
        case NS_ERROR_HARMFUL_URI:
            return @"harmful";
        case NS_ERROR_HARMFULADDON_URI:
            return @"harmfulAddon";
        case NS_ERROR_CONTENT_CRASHED:
            return @"contentCrashed";
        case NS_ERROR_INVALID_CONTENT_ENCODING:
            return @"invalidContentEncoding";
        case NS_ERROR_UNSAFE_CONTENT_TYPE:
            return @"unsafeContentType";
        case NS_ERROR_CORRUPTED_CONTENT:
            return @"corruptedContent";
        case NS_ERROR_NET_RESET:
            return @"netReset";
        case NS_ERROR_NET_INTERRUPT:
            return @"netInterrupt";
        case NS_ERROR_NET_TIMEOUT:
            return @"netTimeout";
        case NS_ERROR_CONNECTION_REFUSED:
            return @"connectionRefused";
        case NS_ERROR_UNKNOWN_SOCKET_TYPE:
            return @"unknownSocketType";
        case NS_ERROR_REDIRECT_LOOP:
            return @"redirectLoop";
        case NS_ERROR_HTTPS_ONLY:
            return @"httpsOnly";
        case NS_ERROR_BAD_HSTS_CERT:
            return @"badHSTSCertificate";
        case NS_ERROR_OS_LOCAL_NETWORK_ACCESS_DENIED:
            return @"localNetworkAccessDenied";
        case NS_ERROR_OFFLINE:
            return @"offline";
        case NS_ERROR_PORT_ACCESS_NOT_ALLOWED:
            return @"portBlocked";
        case NS_ERROR_UNKNOWN_PROTOCOL:
            return @"unknownProtocol";
        case NS_ERROR_UNKNOWN_HOST:
            return @"unknownHost";
        case NS_ERROR_MALFORMED_URI:
            return @"malformedURI";
        case NS_ERROR_FILE_NOT_FOUND:
            return @"fileNotFound";
        case NS_ERROR_FILE_ACCESS_DENIED:
            return @"fileAccessDenied";
        case NS_ERROR_UNKNOWN_PROXY_HOST:
            return @"unknownProxyHost";
        case NS_ERROR_PROXY_CONNECTION_REFUSED:
            return @"proxyConnectionRefused";
        default:
            break;
    }
    
    if (NS_ERROR_GET_MODULE(static_cast<nsresult>(code)) ==
        NS_ERROR_MODULE_SECURITY) {
        if (errorClass == 1) {
            return @"securitySSL";
        }
        
        if (errorClass == 2) {
            return @"securityBadCertificate";
        }
    }
    
    return @"unknown";
}

@end
