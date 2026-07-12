import Testing
@testable import UisgeBeatha

struct CollectionPolicyTests {
    let policy = CollectionPolicy.scotchOnly

    @Test func allowsScotlandOnly() {
        #expect(policy.allows(country: "Scotland"))
        #expect(!policy.allows(country: "Ireland"))
        #expect(!policy.allows(country: "Japan"))
    }

    @Test func clearlyDisallowsKnownNonScotchCategories() {
        #expect(policy.clearlyDisallows(categoryTags: ["en:bourbon-whiskey"]))
        #expect(policy.clearlyDisallows(categoryTags: ["en:irish-whiskeys"]))
        #expect(policy.clearlyDisallows(categoryTags: ["en:vodka"]))
    }

    @Test func ambiguityDoesNotReject() {
        // Missing or unhelpful data must fall through to manual entry, never reject.
        #expect(!policy.clearlyDisallows(categoryTags: []))
        #expect(!policy.clearlyDisallows(categoryTags: ["en:whisky", "en:spirits"]))
        #expect(!policy.clearlyDisallows(categoryTags: ["en:scotch-whisky"]))
    }

    @Test func rejectionCopyUsesWhiskySpelling() {
        #expect(policy.rejectionMessage.contains("whisky"))
        #expect(!policy.rejectionMessage.lowercased().contains("whiskey"))
    }
}
