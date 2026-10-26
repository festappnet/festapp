import 'package:test/test.dart';
import 'package:fstapp/components/search/offline_search_index.dart';

void main() {
  test('projection epoch change rebuilds the local index before searching',
      () async {
    var epoch = 1;
    var loads = 0;
    var documents = [
      const OfflineSearchDocument(
        entityType: 'event',
        entityId: 1,
        title: 'Původní program',
        searchText: 'Původní program',
      ),
    ];
    final cache = OfflineSearchIndexCache(
      loadDocuments: () async {
        loads++;
        return documents;
      },
      readEpoch: () => epoch,
    );

    expect((await cache.search('puvodni')).single.entityId, 1);
    expect(loads, 1);

    documents = [
      const OfflineSearchDocument(
        entityType: 'event',
        entityId: 2,
        title: 'Nově synchronizovaný program',
        searchText: 'Nově synchronizovaný program',
      ),
    ];
    epoch++;

    expect((await cache.search('synchronizovany')).single.entityId, 2);
    expect(await cache.search('puvodni'), isEmpty);
    expect(loads, 2, reason: 'unchanged epoch must reuse the rebuilt index');
  });

  test('offline query over 5000 documents stays interactive', () async {
    final documents = List.generate(
      5000,
      (index) => OfflineSearchDocument(
        entityType: 'event',
        entityId: index,
        title: 'Program číslo $index',
        searchText: index == 4999
            ? 'Program číslo $index unikátní jehla'
            : 'Program číslo $index běžný obsah',
      ),
    );
    final cache = OfflineSearchIndexCache(
      loadDocuments: () async => documents,
      readEpoch: () => 1,
    );

    await cache.search('warmup');
    final stopwatch = Stopwatch()..start();
    final result = await cache.search('unikatni jehla');
    stopwatch.stop();

    expect(result.single.entityId, 4999);
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });
}
