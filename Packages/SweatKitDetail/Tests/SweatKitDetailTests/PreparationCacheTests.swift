import Testing
@testable import SweatKitDetail

@Test func cacheInvalidatesWhenInputsChange() async throws {
    let cache = DetailPreparationCache()
    let input = makeInput(makeStream(count: 3, power: [100, 200, 300]))
    #expect(try await cache.prepare(input).cacheHit == false)
    #expect(try await cache.prepare(input).cacheHit == true)
    var changed = input
    changed.profile = makeProfile(thresholdPower: 250)
    #expect(try await cache.prepare(changed).cacheHit == false)
    changed.stream.power = .init([120, 200, 300])
    #expect(try await cache.prepare(changed).cacheHit == false)
    changed.lapStarts = [1]
    #expect(try await cache.prepare(changed).cacheHit == false)
    await cache.removeAll()
    #expect(try await cache.prepare(changed).cacheHit == false)
}

@Test func cacheEvictsLeastRecentlyUsedActivity() async throws {
    let cache = DetailPreparationCache(capacity: 2)
    let a = makeInput(makeStream(count: 3, power: [100, 100, 100]))
    let b = makeInput(makeStream(count: 3, power: [200, 200, 200]))
    let c = makeInput(makeStream(count: 3, power: [300, 300, 300]))
    _ = try await cache.prepare(a)
    _ = try await cache.prepare(b)
    #expect(try await cache.prepare(a).cacheHit)
    _ = try await cache.prepare(c)
    #expect(try await cache.prepare(a).cacheHit)
    #expect(try await cache.prepare(b).cacheHit == false)
}
