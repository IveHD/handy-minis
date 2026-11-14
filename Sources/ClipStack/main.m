#import "AppController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppController *controller = [AppController shared];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
