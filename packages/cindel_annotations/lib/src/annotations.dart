class Collection {
  const Collection({this.name});

  final String? name;
}

const collection = Collection();

class Index {
  const Index({this.unique = false});

  final bool unique;
}

const index = Index();
