import Testing
@testable import UisgeBeatha

struct BarcodeTests {
    @Test func acceptsValidGTINLengths() {
        #expect(Barcode.normalized("5000281005416") == "5000281005416")
        #expect(Barcode.normalized("96385074") == "96385074")
        #expect(Barcode.normalized("15000281005413") == "15000281005413")
    }

    @Test func padsUPCAToEAN13() {
        #expect(Barcode.normalized("088076161863") == "0088076161863")
    }

    @Test func toleratesSpacesAndDashesBetweenDigitGroups() {
        #expect(Barcode.normalized(" 5 000281 005416 ") == "5000281005416")
        #expect(Barcode.normalized("5000281-005416") == "5000281005416")
    }

    @Test func rejectsNonDigitsAndBadLengths() {
        #expect(Barcode.normalized("") == nil)
        #expect(Barcode.normalized("12345") == nil)
        #expect(Barcode.normalized("500028100541a") == nil)
        #expect(Barcode.normalized("../../etc") == nil)
        #expect(Barcode.normalized("5000281005416?x=1") == nil)
        #expect(Barcode.normalized("123456789012345") == nil)
    }

    @Test func storedVariantsCoverLegacyUPCAForm() {
        #expect(Barcode.storedVariants(of: "0088076161863") == ["0088076161863", "088076161863"])
        #expect(Barcode.storedVariants(of: "5000281005416") == ["5000281005416"])
    }
}
