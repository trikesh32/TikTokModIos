#import <Foundation/Foundation.h>
void TRDInstall(void);
void TRDBeginWindow(NSString *phase);
NSDictionary *TRDModelFields(id object,NSString *family,NSString *field,id result);
NSDictionary *TRDSnapshot(void);
NSDictionary *TRDRegionFields(id dictionary);
NSDictionary *TRDRequestFields(id url,id headers);
#ifdef TAP_TESTING
BOOL TRDTestObserve(Class cls,SEL selector,BOOL returnsObject);
#endif
