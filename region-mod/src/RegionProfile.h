#import <Foundation/Foundation.h>
NSArray<NSDictionary<NSString *,NSString *> *> *TRFProfiles(void);
NSDictionary<NSString *,NSString *> *TRFProfile(NSString *code);
NSDictionary<NSString *,NSString *> *TRFCurrent(void);
NSString *TRFCountry(void);
NSString *TRFOperator(void);
NSString *TRFSavedCountry(void);
BOOL TRFSaveCountry(NSString *code);
// Explicit store arguments make preference migration testable without touching
// a developer's or user's real defaults domain.
NSString *TRFReadSavedCountry(NSUserDefaults *store,NSString *fallback);
BOOL TRFWriteCountry(NSUserDefaults *store,NSString *code);
#ifdef TAP_TESTING
void TRFTestCountry(NSString *code);
#endif
