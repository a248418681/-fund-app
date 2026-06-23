/// 新闻/公告数据模型
class NewsItem {
  final String title;
  final String date;
  final String url;
  final String source;
  final String type; // notice / news / industry

  const NewsItem({
    required this.title,
    this.date = '',
    this.url = '',
    this.source = '',
    this.type = 'news',
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        title: (json['title'] ?? json['TITLE'] ?? json['NOTICETITLE'] ?? '')
            .toString(),
        date: (json['date'] ?? json['SHOWTIME'] ?? json['NOTICEDATE'] ?? '')
            .toString(),
        url: (json['url'] ?? json['URL'] ?? json['NOTICECONTENTURL'] ?? '')
            .toString(),
        source: (json['source'] ?? json['SOURCENAME'] ?? '').toString(),
        type: (json['type'] ?? 'news').toString(),
      );
}
