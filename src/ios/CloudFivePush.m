#import "CloudFivePush.h"
#import <Cordova/CDV.h>

@implementation CloudFivePush{
    NSDictionary *launchNotification;
    void (^_completionHandler)(UIBackgroundFetchResult);
}

- (void)pluginInitialize
{
    // UIApplicationDidFinishLaunchingNotification
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFinishLaunchingWithOptions:) name:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    
    // CloudFivePushDidReceiveRemoteNotification
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNotificationReceived:) name:@"CloudFivePushDidReceiveRemoteNotification" object:nil];
}

// Detect launch-notification
-(void) didFinishLaunchingWithOptions:(NSNotification *) notification {
    NSDictionary *launchOptions = [notification userInfo];
    if (launchOptions) {
        launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
    }
}

// plugin method
- (void)register:(CDVInvokedUrlCommand*)command
{
    _uniqueIdentifier = (NSString*)[command argumentAtIndex:0];
    _callbackId = command.callbackId;
    
    UIApplication *application = [UIApplication sharedApplication];

    if ([application respondsToSelector:@selector(isRegisteredForRemoteNotifications)]) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeBadge|UIUserNotificationTypeSound categories:nil];
        [application registerUserNotificationSettings:settings];
        [application registerForRemoteNotifications];
    } else {
        [application registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];
    }
}


// Send a message back to the javascript which handles all the success/failure stuff
- (void)sendResult:(NSDictionary *)result
{
    CDVPluginResult* response = nil;
    if (result) {
        response = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: result];
        
        [response setKeepCallbackAsBool:YES];
    
        [self.commandDelegate sendPluginResult:response callbackId: _callbackId];
    }
}

-(void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)token
{
    NSLog(@"- CloudFivePush Got token: %@", token);
    _apsToken = [[[[token description] stringByReplacingOccurrencesOfString:@"<"  withString:@""]
                                       stringByReplacingOccurrencesOfString:@">"  withString:@""]
                                       stringByReplacingOccurrencesOfString: @" " withString:@""];
    [self notifyCloudFive];
    
    [self sendResult:@{@"event": @"registration", @"success": @YES, @"token": _apsToken}];
    
    if (launchNotification) {
        [self sendResult:@{@"event": @"message", @"payload": launchNotification} ];
    }
}

-(void) didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    NSLog(@"- CloudFivePush Error registering for push");
    [self sendResult:@{@"event": @"registration", @"success": @NO, @"error": [error localizedDescription]} ];
}

-(void) onNotificationReceived:(NSNotification *) notification
{
    NSLog(@"- CloudFivePush Notification received %@", notification);
    
    _completionHandler = [notification.object[@"handler"] copy];
    
    UIApplication *app = [UIApplication sharedApplication];
    // We only run in the background.  Foreground notifications should already be handled.
    UIApplicationState state = [app applicationState];
    
    NSDictionary *userInfo = [notification.object[@"userInfo"] copy];

    NSDictionary *payload = [userInfo objectForKey:@"aps"];
    NSString *message = [userInfo objectForKey:@"message"];
    NSString *alert = [payload objectForKey:@"alert"];
    NSDictionary *customData = [userInfo objectForKey:@"data"];

    NSString *title = alert;
    NSString *detailButton = nil;
    if (customData) {
        detailButton = @"Details";
    }
    
    if (message == nil) {
        title = [[[NSBundle mainBundle] infoDictionary]  objectForKey:@"CFBundleName"];
        message = alert;
    }
    
    if (alert && state != UIApplicationStateBackground) {
        self.alertUserInfo = userInfo;
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:@"Dismiss" otherButtonTitles:detailButton, nil];
        [alertView show];
    }
    
    [self.commandDelegate runInBackground:^{
        [self sendResult:@{@"event": @"message", @"payload": userInfo} ];
    }];
}

// Plugin method:  Kill the background-process
-(void) finish:(CDVInvokedUrlCommand*)command
{
    NSLog(@"- CloudFivePush finish");
    [self doFinish];
}

// Kill the background-process
-(void) doFinish
{
    if (_completionHandler) {
        _completionHandler(UIBackgroundFetchResultNewData);
        _completionHandler = nil;
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        [self sendResult:@{@"event": @"interaction", @"payload": self.alertUserInfo} ];
        self.alertUserInfo = nil;
    }
}

-(void)notifyCloudFive
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.cloudfiveapp.com/push/register"]];
    request.HTTPMethod = @"POST";
    UIDevice *dev = [UIDevice currentDevice];
    NSString *postData = [NSString stringWithFormat:@"bundle_identifier=%@&device_token=%@&device_platform=ios&device_name=%@&device_model=%@&device_version=%@&app_version=%@",
                            [[NSBundle mainBundle] bundleIdentifier],
                            _apsToken,
                            dev.name,
                            dev.model,
                            dev.systemVersion,
                            [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey]
                          
    ];
    if (_uniqueIdentifier != nil) {
        postData = [postData stringByAppendingFormat:@"&user_identifier=%@", _uniqueIdentifier];
    }

    request.HTTPBody = [postData dataUsingEncoding:NSUTF8StringEncoding];
    NSURLConnection *conn = [NSURLConnection connectionWithRequest:request delegate:self];
    [conn start];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"- CloudFivePush Error talking to cloudfive");
}

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    if ([httpResponse statusCode] == 200) {
        NSLog(@"- CloudFivePush Successfully registered!");
    } else {
        NSLog(@"- CloudFivePush Couldn't register with cloudfive");
    }
}
@end