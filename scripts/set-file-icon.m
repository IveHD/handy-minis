#import <AppKit/AppKit.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:@(argv[1])];
        return icon && [NSWorkspace.sharedWorkspace setIcon:icon forFile:@(argv[2]) options:0] ? 0 : 1;
    }
}
