#import "ObjCTopicToolbarHTMLBuilder.h"

@implementation ObjCTopicToolbarHTMLBuilder

- (NSString *)toolbarHTMLWithBeginEnabled:(BOOL)beginEnabled
                               endEnabled:(BOOL)endEnabled
                               pageNumber:(NSInteger)pageNumber
                           lastPageNumber:(NSInteger)lastPageNumber
                             searchActive:(BOOL)searchActive
                     hasMoreFilteredPosts:(BOOL)hasMoreFilteredPosts {
    if (searchActive) {
        return @"<a href=\"oijlkajsdoihjlkjasdoauto://submitsearch\" id=\"searchintra_nextbutton\">Résultats suivants &raquo;</a>";
    }
    if (hasMoreFilteredPosts) {
        return @"<a href=\"oijlkajsdoihjlkjasdoauto://filterPostsQuotesNext\" id=\"searchintra_nextbutton\">Résultats suivants &raquo;</a>";
    }
    if (pageNumber <= 0 || lastPageNumber <= 0) {
        return @"";
    }

    NSString *buttonBegin = beginEnabled
        ? @"<div class=\"button1\" ontouchstart=\"$(this).addClass(\\'hover\\')\" ontouchend=\"$(this).removeClass(\\'hover\\')\" ><a href=\"oijlkajsdoihjlkjasdoauto://begin\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"38\" height=\"15\" viewBox=\"0 0 38 28\"><defs><style>button_svg_active {fill: var(--color-action);fill-rule: evenodd;}</style></defs><path id=\"Shape1.svg\" class=\"button_svg_active\" d=\"M38,0L23,14,38,28V0ZM22,0L7,14,22,28V0ZM6,0V28H0V0H6Z\"/></svg></a></div>"
        : @"<div class=\"button1\"><a href=\"\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"38\" height=\"15\" viewBox=\"0 0 38 28\"><defs><style>button_svg_disabled {fill: var(--color-action-disabled);fill-rule: evenodd;}</style></defs><path id=\"Shape1.svg\" class=\"button_svg_disabled\" d=\"M38,0L23,14,38,28V0ZM22,0L7,14,22,28V0ZM6,0V28H0V0H6Z\"/></a></svg></div>";
    NSString *buttonPrevious = beginEnabled
        ? @"<div class=\"button2\" ontouchstart=\"$(this).addClass(\\'hover\\')\" ontouchend=\"$(this).removeClass(\\'hover\\')\" ><a href=\"oijlkajsdoihjlkjasdoauto://previous\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"23\" height=\"15\" viewBox=\"0 0 23 28\"><defs><style>button_svg_active {    fill: var(--color-action);fill-rule: evenodd;}</style></defs><path id=\"Shape2.svg\" class=\"button_svg_active\" d=\"M23,0L0,14,23,28V0Z\"/></svg></a></div>"
        : @"<div class=\"button2\"><a href=\"\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"23\" height=\"15\" viewBox=\"0 0 23 28\"><defs><style>button_svg_disabled {    fill: var(--color-action-disabled);fill-rule: evenodd;}</style></defs><path id=\"Shape2.svg\" class=\"button_svg_disabled\" d=\"M23,0L0,14,23,28V0Z\"/></svg></div>";
    NSString *buttonNext = endEnabled
        ? @"<div class=\"button3\" ontouchstart=\"$(this).addClass(\\'hover\\')\" ontouchend=\"$(this).removeClass(\\'hover\\')\" ><a href=\"oijlkajsdoihjlkjasdoauto://next\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"23\" height=\"15\" viewBox=\"0 0 23 28\"><defs><style>button_svg_active {    fill: var(--color-action);fill-rule: evenodd;}</style></defs><path id=\"Shape2.svg\" class=\"button_svg_active\" d=\"M23,0L0,14,23,28V0Z\" transform=\"scale(-1,1) translate(-23,0)\"/></svg></a></div>"
        : @"<div class=\"button3\"><a href=\"\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"23\" height=\"15\" viewBox=\"0 0 23 28\"><defs><style>button_svg_disabled {    fill: var(--color-action-disabled);fill-rule: evenodd;}</style></defs><path id=\"Shape2.svg\" class=\"button_svg_disabled\" d=\"M23,0L0,14,23,28V0Z\" transform=\"scale(-1,1) translate(-23,0)\"/></svg></a></div>";
    NSString *buttonEnd = endEnabled
        ? @"<div class=\"button4\" ontouchstart=\"$(this).addClass(\\'hover\\')\" ontouchend=\"$(this).removeClass(\\'hover\\')\" ><a href=\"oijlkajsdoihjlkjasdoauto://end\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"38\" height=\"15\" viewBox=\"0 0 38 28\"><defs><style>button_svg_active {    fill: var(--color-action);fill-rule: evenodd;}</style></defs><path id=\"Shape4.svg\" class=\"button_svg_active\" d=\"M38,0L23,14,38,28V0ZM22,0L7,14,22,28V0ZM6,0V28H0V0H6Z\" transform=\"scale(-1,1) translate(-38,0)\"/></svg></a></div>"
        : @"<div class=\"button4\"><a href=\"\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"38\" height=\"15\" viewBox=\"0 0 38 28\"><defs><style>button_svg_disabled {    fill: var(--color-action-disabled);fill-rule: evenodd;}</style></defs><path id=\"Shape4.svg\" class=\"button_svg_disabled\" d=\"M38,0L23,14,38,28V0ZM22,0L7,14,22,28V0ZM6,0V28H0V0H6Z\" transform=\"scale(-1,1) translate(-38,0)\"/></svg></a></div>";

    return [NSString stringWithFormat:@"<div id=\"toolbarpage\">%@%@<a href=\"oijlkajsdoihjlkjasdoauto://choose\">%ld / %ld</a>%@%@</div>",
            buttonBegin, buttonPrevious, (long)pageNumber, (long)lastPageNumber, buttonNext, buttonEnd];
}

@end
