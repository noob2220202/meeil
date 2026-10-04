import 'package:flutter/material.dart';

import '../../core/config.dart';
import 'docs.dart';

/// 이용약관 / 개인정보 처리 안내 본문
class DocScreen extends StatelessWidget {
  const DocScreen({super.key, required this.docId});

  final String docId;

  @override
  Widget build(BuildContext context) {
    final doc = legalDocs[docId];
    return Scaffold(
      appBar: AppBar(title: Text(doc?.title ?? '문서'), backgroundColor: Colors.transparent),
      body: doc == null
          ? const Center(child: Text('문서를 찾을 수 없어요.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.body, style: const TextStyle(height: 1.7, fontSize: 15)),
                  const SizedBox(height: 16),
                  const Text('전문은 아래 주소에서 볼 수 있어요.', style: TextStyle(fontSize: 13)),
                  SelectableText(
                    '${AppConfig.webBaseUrl}/legal/${docId == 'terms' ? 'terms' : 'privacy'}',
                    style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
    );
  }
}
