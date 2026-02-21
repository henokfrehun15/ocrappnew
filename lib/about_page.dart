import 'package:flutter/material.dart';

import 'app_language.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.language = AppLanguage.english});

  final AppLanguage language;

  static final Map<AppLanguage, Map<String, String>> _strings = {
    AppLanguage.english: {
      'title': 'About AAOCR',
      'app_name': 'Amharic and Awnig OCR Scanner',
      'version': 'Version 1.0.0',
      'how_to': 'How to Use the App',
      'about_app': 'About the App',
      'about_app_body':
          'AAOCR is an Optical Character Recognition app specifically designed for Amharic text. '
          'It allows you to extract text from images and convert it into editable and shareable formats.',
      'features': 'Features',
      'developed_by': 'Developed By',
    },
    AppLanguage.amharic: {
      'title': 'ስለ AAOCR',
      'app_name': 'የአማርኛ እና አዊኛ OCR ስካነር',
      'version': 'ቅጂ 1.0.0',
      'how_to': 'መተግበሪያውን እንዴት እንደሚጠቀሙ',
      'about_app': 'ስለ መተግበሪያው',
      'about_app_body':
          'AAOCR በተለይ ለአማርኛ ጽሑፍ የተዘጋጀ የቃል ማስታወቂያ መተግበሪያ ነው። '
          'ከምስሎች ጽሑፍ ማውጣት እና ወደ ሊቀየር እና ሊጋራ የሚችል ቅርጽ መቀየር ይፈቅዳል።',
      'features': 'ባህሪያት',
      'developed_by': 'የተሰራ በ',
    },
  };

  static final Map<AppLanguage, List<String>> _howToList = {
    AppLanguage.english: [
      '1. Use scanned images if possible',
      '2. Background must be grayscale or black and white to get good result',
      '3. Ensure good lighting when scanning',
      '4. Text should be clear and properly aligned',
      '5. Avoid shadows or reflections on the document',
    ],
    AppLanguage.amharic: [
      '1. የስካን የተደረጉ ምስሎችን ብቻ ይጠቀሙ',
      '2. የጀርባ ቀለም ነጭ የፊደል ቀለም ጥቁር ቢሆን ይመረጣል',
      '3. ስካን ሲደረግ ጥሩ ብርሃን መኖሩን ያረጋግጡ',
      '4. ጽሑፉ ግልጽ እና በትክክል የተደረደረ መሆን አለበት',
      '5. በሰነዱ ላይ ጥላዎች ወይም መንፀባረቅ እንዳይኖሩ ይጣሩ',
    ],
  };

  static final Map<AppLanguage, List<String>> _featuresList = {
    AppLanguage.english: [
      'Extract Amharic and Awngi text from images',
      'Save results as PDF or text files',
      'Edit recognized text',
      'Scan history tracking',
    ],
    AppLanguage.amharic: [
      'ከምስሎች የአማርኛ እና አዊኛ ጽሑፍ አውጣ',
      'ውጤቶችን እንደ PDF ወይም የጽሑፍ ፋይል አስቀምጥ',
      'የወጡትን ጽሑፍ አስተካክል',
      'የስካን ታሪክ መከታተል',
    ],
  };

  String _t(String key) {
    return _strings[language]?[key] ??
        _strings[AppLanguage.english]?[key] ??
        key;
  }

  List<String> _list(Map<AppLanguage, List<String>> source) {
    return source[language] ?? source[AppLanguage.english] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 60,
                  // backgroundImage: AssetImage('assets/icon.png'),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _t('app_name'),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _t('version'),
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 30),
              Text(
                _t('how_to'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    _list(
                      _howToList,
                    ).map((text) => _buildFeatureItem(text)).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                _t('about_app'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(_t('about_app_body'), style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              Text(
                _t('features'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    _list(
                      _featuresList,
                    ).map((text) => _buildFeatureItem(text)).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                _t('developed_by'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const ListTile(
                leading: Icon(Icons.person),
                title: Text('AGEHY P.L.C'),
                subtitle: Text('agehy@gmail.com'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3, right: 8),
            child: Icon(Icons.check_circle, size: 16, color: Colors.green),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
