#import <Foundation/Foundation.h>
void TRGInstall(void);
NSDictionary *TRGSnapshot(void);
id TRGNormalizeDictionary(id value);
id TRGFeatureValue(id name,id value);
#ifdef TAP_TESTING
BOOL TRGTestInstall(Class cls,SEL selector);
NSDictionary *TRGTimeValues(NSDate *date);
#endif
