#import "TextActions.h"

static NSString *ReplacePattern(NSString *text, NSString *pattern, NSString *replacement) {
    return [text stringByReplacingOccurrencesOfString:pattern withString:replacement
        options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
}

NSString *HandyMinisTransformText(NSString *text, HandyMinisTextAction action) {
    if (action == HandyMinisTextActionSingleLine) {
        return [ReplacePattern(text, @"\\s+", @" ") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    text = ReplacePattern(text, @"\\R", @"\n");
    text = ReplacePattern(text, @"\\h+", @" ");
    text = ReplacePattern(text, @"(?m)^ +| +$", @"");
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (action == HandyMinisTextActionTrimSpaces) return text;

    text = ReplacePattern(text, @"\\n{3,}", @"\n\n");
    // Wrapped CJK text does not need a space between lines.
    NSString *cjk = @"[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}\\p{Block=CJK_Symbols_And_Punctuation}\\p{Block=Halfwidth_And_Fullwidth_Forms}]";
    NSString *joined = [NSString stringWithFormat:@"(?<=%@)\\n(?=%@)", cjk, cjk];
    text = ReplacePattern(text, joined, @"");
    return ReplacePattern(text, @"(?<!\\n)\\n(?!\\n)", @" ");
}
