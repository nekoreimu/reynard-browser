//
//  UIKit+Private.h
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

#import <UIKit/UIKit.h>

typedef struct {
    UIRectEdge attachment;
    UIRectEdge alignment;
    CGFloat attachmentOffset;
    CGFloat alignmentOffset;
    NSInteger gravity;
} ContextMenuAnchor;

@interface _UIContextMenuStyle : NSObject
+ (nonnull instancetype)defaultStyle;
@property(nonatomic) ContextMenuAnchor _preferredAnchor;
@end

@interface UIMenuElement (ReaderSettings)
@property(nonatomic, copy) NSAttributedString *attributedTitle;
@end

API_AVAILABLE(ios(15.0))
@interface UISheetPresentationControllerDetent (ReaderSettings)
+ (instancetype)_detentWithIdentifier:(NSString *)identifier
                             constant:(double)constant;
@end
