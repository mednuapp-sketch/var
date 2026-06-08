// Static weekly pregnancy data — baby development, size comparisons, nutrition

class WeeklyPregnancyData {
  final int week;
  final String babySize;
  final String babySizeComparison;
  final String babyLength; // approximate
  final String babyWeight; // approximate
  final String development;
  final List<String> commonSymptoms;
  final List<String> foodsToEat;
  final List<String> foodsToAvoid;
  final String nutritionTip;
  final String weeklyTip;
  final String motherChanges;
  final List<String> keyNutrients;

  const WeeklyPregnancyData({
    required this.week,
    required this.babySize,
    required this.babySizeComparison,
    required this.babyLength,
    required this.babyWeight,
    required this.development,
    required this.commonSymptoms,
    required this.foodsToEat,
    required this.foodsToAvoid,
    required this.nutritionTip,
    required this.weeklyTip,
    required this.motherChanges,
    required this.keyNutrients,
  });
}

const Map<int, WeeklyPregnancyData> kPregnancyWeekData = {
  4: WeeklyPregnancyData(
    week: 4,
    babySize: '2mm',
    babySizeComparison: 'Poppy seed',
    babyLength: '0.2 cm',
    babyWeight: '< 1g',
    development: 'The embryo is implanting in the uterus. The amniotic sac and yolk sac are forming. Neural tube development begins.',
    commonSymptoms: ['Implantation bleeding', 'Mild cramping', 'Breast tenderness', 'Fatigue', 'Nausea starting'],
    foodsToEat: ['Leafy greens', 'Folate-rich foods', 'Legumes', 'Citrus fruits', 'Fortified cereals'],
    foodsToAvoid: ['Alcohol', 'Raw fish', 'High-mercury fish', 'Unpasteurized dairy'],
    nutritionTip: 'Start taking 400–800mcg folic acid daily to prevent neural tube defects.',
    weeklyTip: 'Take a home pregnancy test and schedule your first prenatal appointment.',
    motherChanges: 'You may experience mild spotting and fatigue as implantation occurs.',
    keyNutrients: ['Folic Acid', 'Iron', 'Calcium', 'Vitamin D'],
  ),
  5: WeeklyPregnancyData(
    week: 5,
    babySize: '4mm',
    babySizeComparison: 'Sesame seed',
    babyLength: '0.4 cm',
    babyWeight: '< 1g',
    development: 'Heart begins to beat. Brain, spinal cord, and organs start forming. The embryo looks like a tiny tadpole.',
    commonSymptoms: ['Morning sickness', 'Fatigue', 'Frequent urination', 'Breast changes', 'Mood swings'],
    foodsToEat: ['Ginger tea', 'Crackers', 'Small frequent meals', 'Protein-rich foods', 'Bananas'],
    foodsToAvoid: ['Spicy foods', 'Alcohol', 'Caffeine (limit)', 'Raw eggs'],
    nutritionTip: 'Eat small meals every 2–3 hours to manage morning sickness.',
    weeklyTip: 'Track your nausea triggers and avoid them. Stay hydrated with small sips.',
    motherChanges: 'Morning sickness may begin. Your uterus is growing to accommodate the embryo.',
    keyNutrients: ['Folic Acid', 'Vitamin B6', 'Ginger', 'Iron'],
  ),
  6: WeeklyPregnancyData(
    week: 6,
    babySize: '6mm',
    babySizeComparison: 'Sweet pea',
    babyLength: '0.6 cm',
    babyWeight: '< 1g',
    development: 'Baby\'s face is forming with dark spots where eyes will be. Arm and leg buds appear. Heart beats ~100 times/minute.',
    commonSymptoms: ['Nausea', 'Vomiting', 'Fatigue', 'Breast tenderness', 'Bloating'],
    foodsToEat: ['Yogurt', 'Whole grains', 'Lean protein', 'Fruits', 'Vegetables'],
    foodsToAvoid: ['Deli meats', 'Soft cheeses', 'Raw sprouts', 'Alcohol'],
    nutritionTip: 'Include dairy or calcium-fortified foods to support early bone development.',
    weeklyTip: 'Your first ultrasound may confirm the heartbeat this week.',
    motherChanges: 'Increased blood volume causes breasts to feel heavier and more sensitive.',
    keyNutrients: ['Calcium', 'Folic Acid', 'Vitamin C', 'Protein'],
  ),
  8: WeeklyPregnancyData(
    week: 8,
    babySize: '1.6 cm',
    babySizeComparison: 'Raspberry',
    babyLength: '1.6 cm',
    babyWeight: '1g',
    development: 'All major organs are forming. Fingers and toes are webbed but present. Baby moves in the womb. Eyes are forming.',
    commonSymptoms: ['Morning sickness', 'Fatigue', 'Food aversions', 'Constipation', 'Heartburn'],
    foodsToEat: ['High-fiber foods', 'Prunes', 'Whole grains', 'Lean meat', 'Fortified cereals'],
    foodsToAvoid: ['Processed foods', 'High-sodium foods', 'Alcohol', 'Raw fish'],
    nutritionTip: 'Increase iron intake to support your growing blood volume.',
    weeklyTip: 'Start thinking about announcing your pregnancy after the first trimester.',
    motherChanges: 'Your uterus is now the size of a large orange. Waistline may be thickening.',
    keyNutrients: ['Iron', 'Folic Acid', 'Fiber', 'Protein'],
  ),
  10: WeeklyPregnancyData(
    week: 10,
    babySize: '3 cm',
    babySizeComparison: 'Kumquat',
    babyLength: '3 cm',
    babyWeight: '4g',
    development: 'Baby is now officially a fetus. All organs, muscles, and nerves are in place. Kidneys produce urine. Tiny fingernails form.',
    commonSymptoms: ['Nausea decreasing', 'Round ligament pain', 'Increased energy', 'Headaches', 'Dizziness'],
    foodsToEat: ['Omega-3 rich fish', 'Nuts', 'Avocados', 'Dark leafy greens', 'Eggs'],
    foodsToAvoid: ['High-mercury fish (shark, swordfish)', 'Alcohol', 'Unpasteurized cheeses'],
    nutritionTip: 'Omega-3 fatty acids support your baby\'s brain development.',
    weeklyTip: 'Consider genetic testing options — talk to your doctor about nuchal translucency scan.',
    motherChanges: 'Morning sickness may ease. Your uterus is now the size of a grapefruit.',
    keyNutrients: ['Omega-3', 'Calcium', 'Vitamin D', 'Iron'],
  ),
  12: WeeklyPregnancyData(
    week: 12,
    babySize: '5.4 cm',
    babySizeComparison: 'Lime',
    babyLength: '5.4 cm',
    babyWeight: '14g',
    development: 'First trimester ends! Baby can open and close fingers. Reflexes develop. Digestive system practices contractions.',
    commonSymptoms: ['Reduced nausea', 'Increased appetite', 'Constipation', 'Skin changes', 'Mild headaches'],
    foodsToEat: ['Protein-rich foods', 'Calcium sources', 'Iron-rich foods', 'Whole grains', 'Fresh fruits'],
    foodsToAvoid: ['Alcohol', 'Excessive caffeine', 'Raw/undercooked meat'],
    nutritionTip: 'Increase your caloric intake by ~300 calories per day in the 2nd trimester.',
    weeklyTip: 'Many women share their pregnancy news after the 12-week mark when risk decreases.',
    motherChanges: 'Your bump may start showing. Energy levels are increasing as morning sickness fades.',
    keyNutrients: ['Protein', 'Calcium', 'Iron', 'Vitamin D'],
  ),
  16: WeeklyPregnancyData(
    week: 16,
    babySize: '11.6 cm',
    babySizeComparison: 'Avocado',
    babyLength: '11.6 cm',
    babyWeight: '100g',
    development: 'Baby can make facial expressions. Eyes move behind closed lids. Hair is growing. Bones getting harder.',
    commonSymptoms: ['Back pain', 'Round ligament pain', 'Increased appetite', 'Nasal congestion', 'Leg cramps'],
    foodsToEat: ['Calcium-rich foods', 'Dark leafy greens', 'Salmon', 'Fortified cereals', 'Beans'],
    foodsToAvoid: ['High-sugar foods', 'Alcohol', 'Raw fish', 'Deli meats'],
    nutritionTip: 'Calcium is crucial now for bone development. Aim for 1000mg daily.',
    weeklyTip: 'You may start feeling baby\'s first movements (quickening) around week 16–20.',
    motherChanges: 'Your bump is clearly visible. You may experience backaches as your center of gravity shifts.',
    keyNutrients: ['Calcium', 'Vitamin D', 'Iron', 'Magnesium'],
  ),
  20: WeeklyPregnancyData(
    week: 20,
    babySize: '16.4 cm',
    babySizeComparison: 'Banana',
    babyLength: '16.4 cm',
    babyWeight: '300g',
    development: 'Halfway through! Baby can hear sounds and may respond to voice. Swallowing amniotic fluid. Sleep cycles established.',
    commonSymptoms: ['Baby movements felt clearly', 'Backache', 'Heartburn', 'Swollen feet', 'Dizziness'],
    foodsToEat: ['Iron-rich foods', 'Vitamin C', 'Protein', 'Complex carbohydrates', 'Plenty of water'],
    foodsToAvoid: ['Spicy foods', 'Carbonated drinks', 'Excessive salt', 'Alcohol'],
    nutritionTip: 'Talk to your baby — their hearing is developing. Bond through sound.',
    weeklyTip: 'Schedule your anatomy scan (anomaly scan) this week to check baby\'s development.',
    motherChanges: 'Anatomy scan week! Your uterus reaches your navel. Baby movements are regular.',
    keyNutrients: ['Iron', 'Protein', 'Calcium', 'Fiber'],
  ),
  24: WeeklyPregnancyData(
    week: 24,
    babySize: '21 cm',
    babySizeComparison: 'Corn cob',
    babyLength: '21 cm',
    babyWeight: '600g',
    development: 'Baby has a chance of survival outside womb (viability milestone). Lungs developing rapidly. Footprints and fingerprints forming.',
    commonSymptoms: ['Braxton Hicks contractions', 'Back pain', 'Heartburn', 'Swelling', 'Shortness of breath'],
    foodsToEat: ['Protein', 'Vitamin C', 'Calcium', 'Iron', 'Omega-3'],
    foodsToAvoid: ['Alcohol', 'Raw fish', 'Excessive sodium', 'Unpasteurized foods'],
    nutritionTip: 'Watch for gestational diabetes symptoms — glucose test typically done at 24–28 weeks.',
    weeklyTip: 'Take your glucose screening test. Start childbirth preparation classes.',
    motherChanges: 'Your bump is growing rapidly. Practice good posture to reduce back pain.',
    keyNutrients: ['Protein', 'Iron', 'Calcium', 'Omega-3', 'Vitamin C'],
  ),
  28: WeeklyPregnancyData(
    week: 28,
    babySize: '25 cm',
    babySizeComparison: 'Eggplant',
    babyLength: '25 cm',
    babyWeight: '1 kg',
    development: 'Third trimester begins! Baby can blink and has eyelashes. Brain is growing rapidly. Can hear and respond to sounds.',
    commonSymptoms: ['Frequent urination', 'Insomnia', 'Leg cramps', 'Heartburn', 'Braxton Hicks'],
    foodsToEat: ['Iron-rich foods', 'Omega-3', 'Calcium', 'Fiber-rich foods', 'Protein'],
    foodsToAvoid: ['Alcohol', 'High-sodium foods', 'Caffeine', 'Gas-causing foods'],
    nutritionTip: 'Eat smaller frequent meals to manage heartburn and make room for baby.',
    weeklyTip: 'Start counting baby kicks — 10 movements in 2 hours is a good sign.',
    motherChanges: 'Third trimester begins. You may feel more tired as baby grows rapidly.',
    keyNutrients: ['Iron', 'Calcium', 'Omega-3', 'Magnesium', 'Fiber'],
  ),
  32: WeeklyPregnancyData(
    week: 32,
    babySize: '28 cm',
    babySizeComparison: 'Squash',
    babyLength: '28 cm',
    babyWeight: '1.7 kg',
    development: 'Baby practices breathing. Skin is less wrinkled. Nails grown to fingertips. Most organ systems mature.',
    commonSymptoms: ['Pelvic pressure', 'Braxton Hicks', 'Shortness of breath', 'Fatigue', 'Back pain'],
    foodsToEat: ['Protein', 'Calcium', 'Iron', 'Vitamin K', 'Healthy fats'],
    foodsToAvoid: ['Gas-causing foods', 'Spicy foods', 'Excessive sugar', 'Alcohol'],
    nutritionTip: 'Vitamin K helps with blood clotting for delivery. Include leafy greens.',
    weeklyTip: 'Prepare your hospital bag. Discuss birth preferences with your doctor.',
    motherChanges: 'Baby drops lower in the pelvis. Breathing may become easier but pressure increases below.',
    keyNutrients: ['Protein', 'Calcium', 'Iron', 'Vitamin K'],
  ),
  36: WeeklyPregnancyData(
    week: 36,
    babySize: '33 cm',
    babySizeComparison: 'Romaine lettuce',
    babyLength: '33 cm',
    babyWeight: '2.6 kg',
    development: 'Baby is almost full term. Lungs are mature. Most babies turn head-down. Gaining weight rapidly.',
    commonSymptoms: ['Pelvic pressure', 'Frequent urination', 'Difficulty sleeping', 'Swelling', 'Nesting instinct'],
    foodsToEat: ['Light meals', 'Dates', 'Raspberry leaf tea', 'Protein', 'Hydrating foods'],
    foodsToAvoid: ['Alcohol', 'High-sodium foods', 'Gas-causing foods', 'Heavy/greasy foods'],
    nutritionTip: 'Studies suggest eating 6 dates/day from week 36 may aid cervical ripening.',
    weeklyTip: 'Your doctor will check baby\'s position. Hospital visits become weekly.',
    motherChanges: 'You\'re almost there! Baby may drop lower, making breathing easier but increasing pelvic pressure.',
    keyNutrients: ['Iron', 'Protein', 'Vitamin C', 'Folate'],
  ),
  40: WeeklyPregnancyData(
    week: 40,
    babySize: '36 cm',
    babySizeComparison: 'Pumpkin',
    babyLength: '36 cm (crown to rump)',
    babyWeight: '3.3–3.5 kg',
    development: 'Full term! Baby\'s skull bones remain unfused to ease delivery. All systems ready. Waiting for labor signals.',
    commonSymptoms: ['Cervix dilation', 'Braxton Hicks intensifying', 'Mucus plug loss', 'Nesting drive', 'Pelvic pressure'],
    foodsToEat: ['Light nutritious meals', 'Energy snacks', 'Dates', 'Hydrating foods', 'Easy-to-digest foods'],
    foodsToAvoid: ['Heavy meals', 'Gassy foods', 'Alcohol'],
    nutritionTip: 'Stay well-hydrated. Labor requires energy — maintain good nutrition.',
    weeklyTip: 'Know your labor signs: regular contractions, water breaking, bloody show. Call your doctor promptly.',
    motherChanges: 'Your baby is ready! Every day now counts. Stay calm, trust your body, trust your team.',
    keyNutrients: ['Hydration', 'Electrolytes', 'Iron', 'Protein'],
  ),
};

WeeklyPregnancyData getWeekData(int week) {
  if (kPregnancyWeekData.containsKey(week)) return kPregnancyWeekData[week]!;
  // Find nearest defined week
  final keys = kPregnancyWeekData.keys.toList()..sort();
  WeeklyPregnancyData nearest = kPregnancyWeekData[keys.first]!;
  for (final k in keys) {
    if (k <= week) nearest = kPregnancyWeekData[k]!;
  }
  return WeeklyPregnancyData(
    week: week,
    babySize: nearest.babySize,
    babySizeComparison: nearest.babySizeComparison,
    babyLength: nearest.babyLength,
    babyWeight: nearest.babyWeight,
    development: nearest.development,
    commonSymptoms: nearest.commonSymptoms,
    foodsToEat: nearest.foodsToEat,
    foodsToAvoid: nearest.foodsToAvoid,
    nutritionTip: nearest.nutritionTip,
    weeklyTip: nearest.weeklyTip,
    motherChanges: nearest.motherChanges,
    keyNutrients: nearest.keyNutrients,
  );
}

const List<String> kAllSymptoms = [
  'Nausea', 'Vomiting', 'Fatigue', 'Heartburn', 'Back pain',
  'Swollen feet', 'Headache', 'Dizziness', 'Cramps', 'Spotting',
  'Breast tenderness', 'Constipation', 'Frequent urination',
  'Mood swings', 'Food cravings', 'Baby movements', 'Leg cramps',
  'Shortness of breath', 'Insomnia', 'Braxton Hicks',
];

const List<String> kAllMoods = [
  'Happy', 'Calm', 'Anxious', 'Excited', 'Tired',
  'Irritable', 'Sad', 'Hopeful', 'Overwhelmed', 'Grateful',
];

const List<Map<String, String>> kStandardCheckups = [
  {'week': '4-8',  'title': 'First Prenatal Visit',        'type': 'routine'},
  {'week': '8-10', 'title': 'Nuchal Translucency Scan',    'type': 'ultrasound'},
  {'week': '11-14','title': 'First Trimester Blood Tests', 'type': 'blood_test'},
  {'week': '16',   'title': 'Maternal Serum Screening',    'type': 'blood_test'},
  {'week': '18-22','title': 'Anomaly Scan (Level II)',      'type': 'ultrasound'},
  {'week': '24-28','title': 'Glucose Tolerance Test',      'type': 'blood_test'},
  {'week': '28',   'title': 'Rh Factor / Anemia Check',    'type': 'blood_test'},
  {'week': '32',   'title': 'Growth Scan',                 'type': 'ultrasound'},
  {'week': '36',   'title': 'Group B Strep Test',          'type': 'blood_test'},
  {'week': '37-38','title': 'Pre-Delivery Check',          'type': 'routine'},
  {'week': '39-40','title': 'NST / BPP Test',              'type': 'scan'},
];
