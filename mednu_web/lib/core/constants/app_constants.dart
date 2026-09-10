class AppConstants {
  AppConstants._();

  static const String appName = 'MedNU';
  static const String appTagline = 'Your Healthcare Companion';
  static const String appDescription =
      'Book doctors, access health records, manage prescriptions — all in one place.';

  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.mednu.mednu';
  static const String appStoreUrl  = 'https://drive.google.com/file/d/15MNHFUUP-nBcq_St9HOqlef90MlwyQlM/view?usp=sharing';
  static const String apkDownloadUrl = 'https://play.google.com/store/apps/details?id=com.mednu.mednu';

  static const String contactEmail = 'support@mednu.in';
  static const String contactPhone = '+91 93907 58684';
  static const String contactAddress = 'MedNU Healthcare Services Pvt. Ltd., Visakhapatnam, Andhra Pradesh, India';

  static const List<String> navItems = [
    'Home', 'Services', 'How It Works', 'Doctors', 'About Us', 'Contact',
  ];

  static const List<Map<String, String>> services = [
    {'title': 'Doctor Consultation', 'icon': '🩺', 'color': 'pink'},
    {'title': 'Video Consultation', 'icon': '📹', 'color': 'purple'},
    {'title': 'Lab Tests', 'icon': '🔬', 'color': 'teal'},
    {'title': 'Diagnostics', 'icon': '🏥', 'color': 'orange'},
    {'title': 'Ambulance', 'icon': '🚑', 'color': 'red'},
    {'title': 'Pregnancy Care', 'icon': '🤱', 'color': 'pink'},
    {'title': 'Nutrition', 'icon': '🥗', 'color': 'green'},
    {'title': 'Physiotherapy', 'icon': '💪', 'color': 'blue'},
    {'title': 'Caregivers', 'icon': '👩‍⚕️', 'color': 'pink'},
    {'title': 'Medical Equipment', 'icon': '🩻', 'color': 'slate'},
    {'title': 'Home Care', 'icon': '🏠', 'color': 'blue'},
    {'title': 'Emergency Services', 'icon': '🆘', 'color': 'red'},
  ];

  static const List<Map<String, String>> whyMednuFeatures = [
    {'title': '24/7 Healthcare', 'desc': 'Round-the-clock access to doctors and support', 'icon': '🕐'},
    {'title': 'Verified Doctors', 'desc': 'All doctors are verified and credentialed', 'icon': '✅'},
    {'title': 'Fast Booking', 'desc': 'Book appointments in under 60 seconds', 'icon': '⚡'},
    {'title': 'Emergency Support', 'desc': 'Instant ambulance and emergency services', 'icon': '🚑'},
    {'title': 'Digital Records', 'desc': 'All your health records in one secure place', 'icon': '📁'},
    {'title': 'Secure Platform', 'desc': 'Your data is encrypted and fully protected', 'icon': '🔒'},
  ];

  static const List<Map<String, String>> testimonials = [
    {
      'name': 'Priya Sharma',
      'location': 'Bengaluru',
      'review': 'MedNU has completely transformed how I manage my family\'s health. Booking a doctor used to take hours — now it\'s just a few taps!',
      'rating': '5',
      'avatar': 'PS',
    },
    {
      'name': 'Rahul Verma',
      'location': 'Mumbai',
      'review': 'The emergency service feature saved my father\'s life. The ambulance arrived in under 10 minutes. Cannot thank MedNU enough.',
      'rating': '5',
      'avatar': 'RV',
    },
    {
      'name': 'Ananya Krishnan',
      'location': 'Chennai',
      'review': 'As a working mom, having all my kids\' health records and prescriptions in one app is a game changer. Highly recommend!',
      'rating': '5',
      'avatar': 'AK',
    },
    {
      'name': 'Mohd. Irfan',
      'location': 'Hyderabad',
      'review': 'The video consultation feature is brilliant. I consulted a specialist without leaving home. Quality care made accessible.',
      'rating': '4',
      'avatar': 'MI',
    },
    {
      'name': 'Deepa Nair',
      'location': 'Kochi',
      'review': 'MedNU\'s pregnancy tracking kept me informed throughout my journey. The weekly updates and checkup reminders were invaluable.',
      'rating': '5',
      'avatar': 'DN',
    },
  ];

  static const List<Map<String, String>> healthArticles = [
    {
      'title': '10 Habits for a Healthier Heart',
      'category': 'Heart Health',
      'time': '5 min read',
      'emoji': '❤️',
    },
    {
      'title': 'Managing Diabetes with Smart Nutrition',
      'category': 'Diabetes Care',
      'time': '4 min read',
      'emoji': '🩺',
    },
    {
      'title': 'Mental Wellness in the Digital Age',
      'category': 'Mental Health',
      'time': '6 min read',
      'emoji': '🧠',
    },
    {
      'title': 'Pregnancy Nutrition: First Trimester Guide',
      'category': 'Pregnancy',
      'time': '7 min read',
      'emoji': '🤱',
    },
    {
      'title': 'Building Immunity Naturally',
      'category': 'Nutrition',
      'time': '3 min read',
      'emoji': '🛡️',
    },
    {
      'title': 'Sleep Science: Why 8 Hours Matters',
      'category': 'Wellness',
      'time': '5 min read',
      'emoji': '😴',
    },
  ];
}
