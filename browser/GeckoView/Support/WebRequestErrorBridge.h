//
//  WebRequestErrorBridge.h
//  Reynard
//
//  Created by Minh Ton on 18/10/26.
//

#ifndef WebRequestErrorBridge_h
#define WebRequestErrorBridge_h

#import <Foundation/Foundation.h>

@interface WebRequestErrorBridge : NSObject

+ (nonnull NSString *)loadErrorNameForCode:(uint32_t)code
                                errorClass:(NSInteger)errorClass
NS_SWIFT_NAME(loadErrorName(forCode:errorClass:));

@end

#endif /* WebRequestErrorBridge_h */
