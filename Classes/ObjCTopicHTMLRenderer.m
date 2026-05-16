#import "ObjCTopicHTMLRenderer.h"

#import "ObjCTopicHTMLRenderContext.h"
#import "ThemeColors.h"
#import "ThemeManager.h"

@implementation ObjCTopicHTMLRenderer

- (NSString *)renderHTMLWithContext:(ObjCTopicHTMLRenderContext *)context {
    NSString *displaySignatureClass = [[[NSUserDefaults standardUserDefaults] stringForKey:@"display_sig"] isEqualToString:@"yes"] ? @"" : @"nosig";
    NSString *doubleSmileysCSS = @".smileycustom {max-height:45px;}";
    Theme theme = [[ThemeManager sharedManager] theme];
    NSString *avatarImageFile = @"url(avatar_male_gray_on_light_48x48.png)";
    NSString *loadInfoImageFile = @"url(loadinfo.gif)";
    if (theme == ThemeDark) {
        avatarImageFile = @"url(avatar_male_gray_on_dark_48x48.png)";
        loadInfoImageFile = @"url(loadinfo.net.gif)";
    }

    NSString *html = [NSString stringWithFormat:@"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\
                      <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"fr\" lang=\"fr\">\
                      <head>\
                      <script type='text/javascript' src='jquery-2.1.1.min.js'></script>\
                      <script type='text/javascript' src='jquery.doubletap.js'></script>\
                      <script type='text/javascript' src='jquery.base64.js'></script>\
                      <meta name='viewport' content='initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no' />\
                      <meta http-equiv='Content-Type' content='text/html; charset=UTF-8' />\
                      <link type='text/css' rel='stylesheet' href='style-liste-light.css' id='light-styles'/>\
                      <style type='text/css'>%@</style>\
                      <style id='smileys_double' type='text/css'>%@</style>\
                      </head><body class='iosversion'><a name='top' id='top'></a>\
                      <div class='bunselected %@' id='qsdoiqjsdkjhqkjhqsdqdilkjqsd2'>%@</div>\
                      %@%@\
                      <div id='endofpage'></div><div id='endofpagetoolbar'></div><a name='bas'></a>\
                      <script type='text/javascript'>\
                      document.addEventListener('DOMContentLoaded', loadedML);\
                      document.addEventListener('touchstart', touchstart);\
                      function loadedML() { setTimeout(function() {document.location.href = 'oijlkajsdoihjlkjasdoloaded://loaded';},700); };\
                      function toggleDiv(id) { $(id).slideToggle('slow'); };\
                      function HLtxt() { var el = document.getElementById('qsdoiqjsdkjhqkjhqsdqdilkjqsd');el.className='bselected'; }\
                      function UHLtxt() { var el = document.getElementById('qsdoiqjsdkjhqkjhqsdqdilkjqsd');el.className='bunselected'; }\
                      function swap_spoiler_states(obj){var div=obj.getElementsByTagName('div');if(div[0]){if(div[0].style.visibility==\"visible\"){div[0].style.visibility='hidden';}else if(div[0].style.visibility==\"hidden\"||!div[0].style.visibility){div[0].style.visibility='visible';}}}\
                      $('img').error(function(){var failingSrc = $(this).attr('src');if(failingSrc.indexOf('https://reho.st')>-1){$(this).attr('src', 'photoDefaultClic.png')}else{$(this).attr('src', 'photoDefaultfailmini.png');}});\
                      function touchstart() { document.location.href = 'oijlkajsdoihjlkjasdotouch://touchstart'};\
                      function touchHeaderMessage(selectedNode, actionName) { event.stopPropagation(); var rect = selectedNode.getBoundingClientRect(); var parentRect = selectedNode.parentNode.getBoundingClientRect(); var x = Math.round(rect.left + (rect.width / 2)); var y = Math.round(parentRect.top); window.location = 'oijlkajsdoihjlkjasdopopup'+actionName+'://'+x+'/'+y+'/' + selectedNode.parentNode.parentNode.id; return false; };\
                      document.documentElement.style.setProperty('--color-action', '%@');\
                      document.documentElement.style.setProperty('--color-action-disabled', '%@');\
                      document.documentElement.style.setProperty('--color-message-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-modo-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-header-me-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-mequoted-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-mequoted-borderleft', '%@');\
                      document.documentElement.style.setProperty('--color-message-mequoted-borderother', '%@');\
                      document.documentElement.style.setProperty('--color-message-header-love-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-quoted-love-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-quoted-love-borderleft', '%@');\
                      document.documentElement.style.setProperty('--color-message-quoted-love-borderother', '%@');\
                      document.documentElement.style.setProperty('--color-message-quoted-bl-background', '%@');\
                      document.documentElement.style.setProperty('--color-message-header-bl-background', '%@');\
                      document.documentElement.style.setProperty('--color-separator-new-message', '%@');\
                      document.documentElement.style.setProperty('--color-text', '%@');\
                      document.documentElement.style.setProperty('--color-text2', '%@');\
                      document.documentElement.style.setProperty('--color-background-bars', '%@');\
                      document.documentElement.style.setProperty('--color-searchintra-nextresults', '%@');\
                      document.documentElement.style.setProperty('--imagefile-avatar', '%@');\
                      document.documentElement.style.setProperty('--imagefile-loadinfo', '%@');\
                      document.documentElement.style.setProperty('--color-border-quotation', '%@');\
                      document.documentElement.style.setProperty('--color-border-avatar', '%@');\
                      document.documentElement.style.setProperty('--color-text-pseudo', '%@');\
                      document.documentElement.style.setProperty('--color-text-pseudo-bl', '%@');\
                      document.documentElement.style.setProperty('--border-header', 'none');\
                      </script></body></html>",
                      context.customFontSizeCSS ?: @"",
                      doubleSmileysCSS,
                      displaySignatureClass,
                      context.messagesHTML ?: @"",
                      context.refreshButtonHTML ?: @"",
                      context.toolbarHTML ?: @"",
                      [ThemeColors hexFromUIColor:[ThemeColors tintColor]],
                      [ThemeColors hexFromUIColor:[ThemeColors tintColorDisabled:theme]],
                      [ThemeColors hexFromUIColor:[ThemeColors messageBackgroundColor:theme]],
                      [ThemeColors hexFromUIColor:[ThemeColors messageModoBackgroundColor:theme]],
                      [[NSUserDefaults standardUserDefaults] integerForKey:@"theme_style"] == 1 ? [ThemeColors rgbaFromUIColor:[ThemeColors tintColor] withAlpha:0.03] : [ThemeColors rgbaFromUIColor:[ThemeColors tintColor] withAlpha:0.15],
                      [ThemeColors rgbaFromUIColor:[ThemeColors tintColor] withAlpha:0.03],
                      [ThemeColors rgbaFromUIColor:[ThemeColors tintColor] withAlpha:1],
                      [ThemeColors rgbaFromUIColor:[ThemeColors tintLightColorNoAlpha]],
                      [[NSUserDefaults standardUserDefaults] integerForKey:@"theme_style"] == 1 ? [ThemeColors rgbaFromUIColor:[ThemeColors loveColor] withAlpha:0.4] : [ThemeColors rgbaFromUIColor:[ThemeColors loveColor] withAlpha:1.0],
                      [ThemeColors rgbaFromUIColor:[ThemeColors loveColor] withAlpha:0.3],
                      [ThemeColors rgbaFromUIColor:[ThemeColors loveColor] withAlpha:1.0 addSaturation:1 addBrightness:1],
                      [ThemeColors rgbaFromUIColor:[ThemeColors loveLightColorNoAlpha]],
                      [ThemeColors rgbaFromUIColor:[ThemeColors textColor:theme] withAlpha:0.05],
                      [ThemeColors rgbaFromUIColor:[ThemeColors textFieldBackgroundColor:theme] withAlpha:0.7],
                      [ThemeColors rgbaFromUIColor:[ThemeColors textColorPseudo:theme] withAlpha:0.5],
                      [ThemeColors hexFromUIColor:[ThemeColors textColor:theme]],
                      [ThemeColors hexFromUIColor:[ThemeColors textColor2:theme]],
                      [ThemeColors hexFromUIColor:[ThemeColors textFieldBackgroundColor:theme]],
                      [ThemeColors rgbaFromUIColor:[ThemeColors textFieldBackgroundColor:theme] withAlpha:0.9],
                      avatarImageFile,
                      loadInfoImageFile,
                      [ThemeColors getColorBorderQuotation:theme],
                      [ThemeColors hexFromUIColor:[ThemeColors getColorBorderAvatar:theme]],
                      [ThemeColors hexFromUIColor:[ThemeColors textColorPseudo:theme]],
                      [ThemeColors rgbaFromUIColor:[ThemeColors textColorPseudo:theme] withAlpha:0.5]];
    return [html stringByReplacingOccurrencesOfString:@"iosversion" withString:(context.searchActive ? @"ios7 searchintra" : @"ios7")];
}

@end
