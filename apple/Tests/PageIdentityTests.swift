import Testing

struct PageIdentityTests {
    @Test func aPagesTaskIsKeyedOnItsOwnId() {
        #expect(PageIdentity.taskID("adventuresofsuperman", load: 3) != PageIdentity.taskID("wendywarrenandthenews", load: 3))
        #expect(PageIdentity.taskID("a", load: 1) != PageIdentity.taskID("a", load: 2), "a new catalog reloads")
        #expect(PageIdentity.taskID("a", load: 1) == PageIdentity.taskID("a", load: 1))
    }
}
