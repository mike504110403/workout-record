/// Web 沒有舊 iOS App 的 CoreData 檔,全部 no-op(介面跟 io 版相同)。
class LegacyCoreDataFiles {
  const LegacyCoreDataFiles({Future<String> Function()? supportDirPathProvider});

  Future<bool> exists() async => false;

  Future<int> deleteAll() async => 0;
}
