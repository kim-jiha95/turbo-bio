#import "TurboBio.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <React/RCTUtils.h>
#import <Security/Security.h>

@implementation TurboBio {
    LAContext *_authContext;
    dispatch_queue_t _authQueue;
    BOOL _isAuthInProgress;
}

RCT_EXPORT_MODULE()

- (instancetype)init {
    if (self = [super init]) {
        _authContext = nil;
        _authQueue = dispatch_queue_create("com.turbobio.auth", DISPATCH_QUEUE_SERIAL);
        _isAuthInProgress = NO;  
    }
    return self;
}

RCT_EXPORT_METHOD(isSensorAvailable:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSError *error = nil;
    LAContext *context = [[LAContext alloc] init];
    
    BOOL canEvaluate = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
    
    if (error) {
        NSString *errorCode = @"";
        
        switch (error.code) {
            case LAErrorBiometryLockout:
                errorCode = @"biometry_lockout";
                break;
            case LAErrorBiometryNotAvailable:
                errorCode = @"biometry_not_available";
                break;
            case LAErrorBiometryNotEnrolled:
                errorCode = @"biometry_not_enrolled";
                break;
            default:
                errorCode = [NSString stringWithFormat:@"error_%ld", (long)error.code];
                break;
        }
        
        reject(errorCode,
               error.localizedDescription,
               error);
        return;
    }
    
    if (canEvaluate) {
        NSString *biometryType = @"";
        if (@available(iOS 11.0, *)) {
            switch(context.biometryType) {
                case LABiometryTypeTouchID:
                    biometryType = @"TouchID";
                    break;
                case LABiometryTypeFaceID:
                    biometryType = @"FaceID";
                    break;
                default:
                    biometryType = @"";
            }
        }
        
        resolve(@{
            @"available": @YES,
            @"biometryType": biometryType
        });
    } else {
        reject(@"biometry_not_available",
               @"Biometrics not available",
               nil);
    }
}

RCT_EXPORT_METHOD(createKeys:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    // 기존 키가 있다면 먼저 삭제
    NSData *deletedTag = [@"com.turbobio.keys" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *deleteQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: deletedTag,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
    
    CFErrorRef error = NULL;
    
    // 도메인 상태 저장
    LAContext *context = [[LAContext alloc] init];
    [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:NULL];
    NSData *domainState = context.evaluatedPolicyDomainState;
    if (domainState) {
        [[NSUserDefaults standardUserDefaults] setObject:domainState forKey:@"TurboBioBiometricDomainState"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    SecAccessControlRef sacObject = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                  kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                                  kSecAccessControlBiometryAny |
                                                                  kSecAccessControlPrivateKeyUsage,
                                                                  &error);
    
    if (error != NULL || sacObject == NULL) {
        NSError *err = (__bridge NSError *)error;
        reject(@"error_creating_keys", [err localizedDescription], err);
        if (error) CFRelease(error);
        return;
    }
    
    NSData *tag = [@"com.turbobio.keys" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *privateKeyAttrs = @{
        (__bridge id)kSecAttrIsPermanent: @YES,
        (__bridge id)kSecAttrApplicationTag: tag,
        (__bridge id)kSecAttrAccessControl: (__bridge id)sacObject,
    };
    
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecAttrIsPermanent: @YES,
        (__bridge id)kSecPrivateKeyAttrs: privateKeyAttrs
    };
    
    SecKeyRef privateKey = NULL;
    OSStatus status = SecKeyGeneratePair((__bridge CFDictionaryRef)attributes, NULL, &privateKey);
    
    if (status == errSecSuccess && privateKey != NULL) {
        SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
        NSData *publicKeyData = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKey, NULL);
        
        NSString *publicKeyString = [publicKeyData base64EncodedStringWithOptions:0];
        
        resolve(@{@"publicKey": publicKeyString});
        
        if (publicKey) CFRelease(publicKey);
        if (privateKey) CFRelease(privateKey);
    } else {
        NSString *errorMessage = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
        reject(@"error_generating_keys", errorMessage ?: @"Failed to generate key pair", nil);
    }
    
    if (sacObject) CFRelease(sacObject);
}


RCT_EXPORT_METHOD(biometricKeysExist:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Checking biometric keys existence");
    
    LAContext *context = [[LAContext alloc] init];
    NSError *authError = nil;
    
    // 생체 인증 키 존재 여부 확인
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        NSLog(@"Biometric authentication not available: %@", authError.localizedDescription);

        // 생체인증 잠금 시 biometry_lockout 반환
        if (authError.code == LAErrorBiometryLockout) {
            NSLog(@"Biometry is locked out, but keys exist.");
            resolve(@{@"keysExist": @YES});
        } else {
            resolve(@{@"keysExist": @NO});
        }
        return;
    }
    
    NSData *currentDomainState = context.evaluatedPolicyDomainState;
    NSData *storedDomainState = [[NSUserDefaults standardUserDefaults] objectForKey:@"TurboBioBiometricDomainState"];
    if (storedDomainState && ![storedDomainState isEqualToData:currentDomainState]) {
        NSLog(@"Biometric enrollment changed. Keys are invalidated.");
        resolve(@{@"keysExist": @NO});
        return;
    }
    
    NSData *tag = [@"com.turbobio.keys" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tag,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecReturnRef: @YES,
        (__bridge id)kSecUseAuthenticationContext: context,
        (__bridge id)kSecUseAuthenticationUI: (__bridge id)kSecUseAuthenticationUISkip
    };
    
    SecKeyRef privateKey = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
    BOOL exists = (status == errSecSuccess);
    
    if (privateKey) CFRelease(privateKey);
    
    NSLog(@"Keys exist: %@", exists ? @"YES" : @"NO");
    
    resolve(@{@"keysExist": @(exists)});
}

RCT_EXPORT_METHOD(deleteKeys:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSData *tag = [@"com.turbobio.keys" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tag,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom
    };
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    resolve(@{@"keysDeleted": @(status == errSecSuccess || status == errSecItemNotFound)});
}

RCT_EXPORT_METHOD(createSignature:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_async(_authQueue, ^{
        if (self->_isAuthInProgress) {
            reject(@"auth_in_progress", @"Authentication already in progress", nil);
            return;
        }
        
        self->_isAuthInProgress = YES;
        
        if (self->_authContext != nil) {
            self->_authContext = nil;
        }
        
        LAContext *context = [[LAContext alloc] init];
        context.localizedFallbackTitle = @"";
        NSError *authError = nil;
        [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError];

        if (authError && authError.code == LAErrorBiometryLockout) {
            self->_isAuthInProgress = NO;  // 인증 상태 초기화
            reject(@"biometry_lockout", @"Biometry is locked due to multiple failed attempts", authError);
            return;
        }

        NSData *currentDomainState = context.evaluatedPolicyDomainState;
        NSData *storedDomainState = [[NSUserDefaults standardUserDefaults] objectForKey:@"TurboBioBiometricDomainState"];
        
        if (storedDomainState && ![storedDomainState isEqualToData:currentDomainState]) {
            self->_isAuthInProgress = NO;  // 인증 상태 초기화
            reject(@"biometric_changed", @"Biometric enrollment has changed", nil);
            return;
        }
        
        self->_authContext = context;
        NSString *promptMessage = options[@"promptMessage"];
        NSString *payload = options[@"payload"];
        
        if (!promptMessage || !payload) {
            self->_authContext = nil;
            self->_isAuthInProgress = NO;  // 인증 상태 초기화
            reject(@"invalid_params", @"Missing required parameters", nil);
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_authContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                              localizedReason:promptMessage
                                       reply:^(BOOL success, NSError *error) {
                dispatch_async(self->_authQueue, ^{
                    if (!success) {
                        self->_authContext = nil;
                        self->_isAuthInProgress = NO;  // 인증 상태 초기화
                        reject(@"authentication_failed", @"Biometric authentication failed", error);
                        return;
                    }

                    NSData *tag = [@"com.turbobio.keys" dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *query = @{
                        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
                        (__bridge id)kSecAttrApplicationTag: tag,
                        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                        (__bridge id)kSecReturnRef: @YES,
                        (__bridge id)kSecUseAuthenticationContext: self->_authContext,
                        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave
                    };
                    
                    SecKeyRef privateKey = NULL;
                    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
                    
                    if (status != errSecSuccess || privateKey == NULL) {
                        reject(@"no_keys", @"No private key found", nil);
                        self->_authContext = nil;
                        return;
                    }
                    
                    NSData *dataToSign = [payload dataUsingEncoding:NSUTF8StringEncoding];
                    CFErrorRef signError = NULL;
                    
                    NSData *signature = (NSData *)CFBridgingRelease(
                        SecKeyCreateSignature(privateKey,
                                              kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                              (__bridge CFDataRef)dataToSign,
                                              &signError)
                    );
                    
                    if (signature) {
                        NSString *signatureString = [signature base64EncodedStringWithOptions:0];
                        resolve(@{@"success": @YES, @"signature": signatureString});
                    } else {
                        NSError *errorDetail = (__bridge NSError *)signError;
                        reject(@"signing_failed", @"Failed to create signature", errorDetail);
                    }
                    
                    if (privateKey) CFRelease(privateKey);
                    self->_authContext = nil;
                    self->_isAuthInProgress = NO;  // 인증 상태 초기화
                });
            }];
        });
    });
}

RCT_EXPORT_METHOD(simplePrompt:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_async(_authQueue, ^{
        if (self->_isAuthInProgress) {
            reject(@"auth_in_progress", @"Authentication already in progress", nil);
            return;
        }
        
        self->_isAuthInProgress = YES;
        self->_authContext = [[LAContext alloc] init];

        NSString *promptMessage = options[@"promptMessage"];
        
        if (!promptMessage) {
            self->_authContext = nil;
            self->_isAuthInProgress = NO;
            reject(@"invalid_params", @"Missing prompt message", nil);
            return;
        }
        
        // 생체인증 시도
        [self authenticateWithBiometrics:promptMessage resolver:resolve rejecter:reject];
    });
}


- (void)authenticateWithBiometrics:(NSString *)promptMessage
                          resolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_authContext = [[LAContext alloc] init];
        self->_authContext.localizedFallbackTitle = @"";  // 암호 입력 버튼 없애기

        [self->_authContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                          localizedReason:promptMessage
                                   reply:^(BOOL success, NSError *error) {
            dispatch_async(self->_authQueue, ^{
                if (success) {
                    resolve(@{@"success": @YES});
                } else if (error.code == LAErrorBiometryLockout) {
                    // 생체인증 잠금 시 패스코드 인증 요청
                    [self handleBiometryLockoutWithResolver:resolve rejecter:reject promptMessage:promptMessage];
                    return;
                } else {
                    resolve(@{
                        @"success": @NO,
                        @"error": error.localizedDescription ?: @"Authentication failed"
                    });
                }
                self->_authContext = nil;
                self->_isAuthInProgress = NO;
            });
        }];
    });
}

// 패스코드 인증 처리 메서드 수정
- (void)handleBiometryLockoutWithResolver:(RCTPromiseResolveBlock)resolve
                                 rejecter:(RCTPromiseRejectBlock)reject
                            promptMessage:(NSString *)promptMessage
{
    LAContext *passcodeContext = [[LAContext alloc] init];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [passcodeContext evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                       localizedReason:@"Biometry is locked. Please enter your passcode to unlock."
                                 reply:^(BOOL success, NSError *error) {
            dispatch_async(self->_authQueue, ^{
                if (success) {
                    // 패스코드 인증 성공 후 생체인증 재시도
                    self->_authContext = [[LAContext alloc] init];
                    [self authenticateWithBiometrics:promptMessage resolver:resolve rejecter:reject];
                } else {
                    reject(@"passcode_failed", @"Passcode authentication failed", error);
                    self->_authContext = nil;
                    self->_isAuthInProgress = NO;
                }
            });
        }];
    });
}

@end
