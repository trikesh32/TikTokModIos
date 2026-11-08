#import <Foundation/Foundation.h>

BOOL TAPCompatBool(Class cls, NSString *selector, BOOL value, BOOL booleanArgument);
BOOL TAPCompatString(Class cls, NSString *selector, NSString *value);
BOOL TAPCompatResource(Class cls, id target, NSString *selector);
void TAPInstallModCompatibility(void);
