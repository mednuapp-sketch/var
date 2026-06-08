class DocData {
  final String id;
  final String name;
  final String spec;
  final String qual;
  final double rating;
  final int reviews;
  final int exp;
  final bool online;
  final int fee;
  final String img;
  final String about;
  final List<String> specialities;

  const DocData({
    required this.id,
    required this.name,
    required this.spec,
    required this.qual,
    required this.rating,
    required this.reviews,
    required this.exp,
    required this.online,
    required this.fee,
    required this.img,
    required this.about,
    required this.specialities,
  });
}

