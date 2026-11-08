#import <Foundation/Foundation.h>

NSDictionary *TAPCodes(id object);
NSDictionary *TAPError(id object);
NSDictionary *TAPEndpoint(id object);
BOOL TAPInstallSerializer(Class cls, BOOL model);
void TAPInstallGuardObserver(BOOL privateKey);
NSDictionary *TAPRequestMetadata(id url, id headers);
void TAPEmit(NSDictionary *fields);
void TAPInstallAttestObserver(Class cls, NSString *name, BOOL keyOnly);
NSDictionary *TAPResponseMetadata(id headers);
NSDictionary *TAPOIDCContext(id context);
void TAPInstallOIDCObservers(Class keyClass, Class flowClass, Class googleClass);

