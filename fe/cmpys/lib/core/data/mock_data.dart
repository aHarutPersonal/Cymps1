/// Mock data for development and testing.
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

// ============================================
// IDOLS
// ============================================

class MockIdol {
  const MockIdol({
    required this.id,
    required this.name,
    required this.initials,
    this.imageUrl,
    this.profession,
    this.birthYear,
    this.netWorth,
    this.description,
  });

  final String id;
  final String name;
  final String initials;
  final String? imageUrl;
  final String? profession;
  final int? birthYear;
  final String? netWorth;
  final String? description;
}

final mockIdols = [
  const MockIdol(
    id: '1',
    name: 'Elon Musk',
    initials: 'EM',
    profession: 'Entrepreneur, CEO',
    birthYear: 1971,
    netWorth: '\$180B+',
    description: 'CEO of Tesla & SpaceX, founder of Neuralink and The Boring Company.',
  ),
  const MockIdol(
    id: '2',
    name: 'Steve Jobs',
    initials: 'SJ',
    profession: 'Entrepreneur, Visionary',
    birthYear: 1955,
    netWorth: '\$10B (2011)',
    description: 'Co-founder of Apple Inc., revolutionized personal computing and mobile phones.',
  ),
  const MockIdol(
    id: '3',
    name: 'Mark Zuckerberg',
    initials: 'MZ',
    profession: 'Entrepreneur, CEO',
    birthYear: 1984,
    netWorth: '\$100B+',
    description: 'Co-founder and CEO of Meta (formerly Facebook).',
  ),
  const MockIdol(
    id: '4',
    name: 'Jeff Bezos',
    initials: 'JB',
    profession: 'Entrepreneur, Investor',
    birthYear: 1964,
    netWorth: '\$150B+',
    description: 'Founder of Amazon and Blue Origin.',
  ),
  const MockIdol(
    id: '5',
    name: 'Bill Gates',
    initials: 'BG',
    profession: 'Philanthropist, Entrepreneur',
    birthYear: 1955,
    netWorth: '\$130B+',
    description: 'Co-founder of Microsoft, philanthropist.',
  ),
  const MockIdol(
    id: '6',
    name: 'Oprah Winfrey',
    initials: 'OW',
    profession: 'Media Executive, Host',
    birthYear: 1954,
    netWorth: '\$2.5B+',
    description: 'Media mogul and talk show host.',
  ),
];

final mockSuggestedIdols = mockIdols.take(3).toList();
final mockPopularIdols = mockIdols.skip(2).take(4).toList();

// ============================================
// TIMELINE / MILESTONES
// ============================================

class MockMilestone {
  const MockMilestone({
    required this.id,
    required this.title,
    required this.age,
    required this.category,
    this.description,
    this.isUserMilestone = false,
    this.isCompleted = false,
  });

  final String id;
  final String title;
  final int age;
  final String category;
  final String? description;
  final bool isUserMilestone;
  final bool isCompleted;
}

final mockIdolMilestones = [
  const MockMilestone(
    id: '1',
    title: 'Started first company (Zip2)',
    age: 24,
    category: 'Career',
    description: 'Co-founded Zip2 with his brother Kimbal.',
  ),
  const MockMilestone(
    id: '2',
    title: 'Sold Zip2 for \$307M',
    age: 28,
    category: 'Finance',
    description: 'Compaq acquired Zip2.',
  ),
  const MockMilestone(
    id: '3',
    title: 'Co-founded X.com (PayPal)',
    age: 28,
    category: 'Career',
    description: 'Started online banking company.',
  ),
  const MockMilestone(
    id: '4',
    title: 'Founded SpaceX',
    age: 31,
    category: 'Career',
    description: 'Founded Space Exploration Technologies Corp.',
  ),
  const MockMilestone(
    id: '5',
    title: 'Joined Tesla as Chairman',
    age: 33,
    category: 'Career',
    description: 'Led Series A funding round.',
  ),
];

final mockUserMilestones = [
  const MockMilestone(
    id: 'u1',
    title: 'Graduated from university',
    age: 22,
    category: 'Learning',
    isUserMilestone: true,
    isCompleted: true,
  ),
  const MockMilestone(
    id: 'u2',
    title: 'First job in tech',
    age: 23,
    category: 'Career',
    isUserMilestone: true,
    isCompleted: true,
  ),
  const MockMilestone(
    id: 'u3',
    title: 'Started side project',
    age: 25,
    category: 'Career',
    isUserMilestone: true,
    isCompleted: true,
  ),
];

// ============================================
// CATEGORIES
// ============================================

class MockCategory {
  const MockCategory({
    required this.name,
    required this.icon,
    required this.progress,
    required this.color,
    this.gap,
  });

  final String name;
  final String icon;
  final double progress;
  final Color color;
  final String? gap;
}

final mockCategories = [
  MockCategory(
    name: 'Career',
    icon: 'assets/icons/briefcase.svg',
    progress: 0.68,
    color: AppColors.accent,
    gap: 'Start a company',
  ),
  MockCategory(
    name: 'Learning',
    icon: 'assets/icons/graduation_cap.svg',
    progress: 0.75,
    color: AppColors.info,
    gap: 'Complete advanced degree',
  ),
  MockCategory(
    name: 'Finance',
    icon: 'assets/icons/dollar_sign.svg',
    progress: 0.45,
    color: AppColors.success,
    gap: 'Build investment portfolio',
  ),
  MockCategory(
    name: 'Impact',
    icon: 'assets/icons/heart.svg',
    progress: 0.52,
    color: AppColors.warning,
    gap: 'Start giving back',
  ),
  MockCategory(
    name: 'Skills',
    icon: 'assets/icons/brain.svg',
    progress: 0.61,
    color: const Color(0xFFEC4899),
    gap: 'Learn leadership',
  ),
];

// ============================================
// PLAN ITEMS
// ============================================

class MockPlanItem {
  const MockPlanItem({
    required this.id,
    required this.title,
    required this.category,
    this.dueDate,
    this.isCompleted = false,
    this.priority = 'medium',
  });

  final String id;
  final String title;
  final String category;
  final String? dueDate;
  final bool isCompleted;
  final String priority;
}

final mockTodayPlan = [
  const MockPlanItem(
    id: 'p1',
    title: 'Read "Zero to One" - Chapter 3',
    category: 'Learning',
    isCompleted: true,
  ),
  const MockPlanItem(
    id: 'p2',
    title: 'Complete Python course module',
    category: 'Skills',
    isCompleted: true,
  ),
  const MockPlanItem(
    id: 'p3',
    title: 'Review investment portfolio',
    category: 'Finance',
    isCompleted: false,
  ),
  const MockPlanItem(
    id: 'p4',
    title: 'Network with industry leaders',
    category: 'Career',
    isCompleted: false,
  ),
  const MockPlanItem(
    id: 'p5',
    title: 'Write reflection journal',
    category: 'Impact',
    isCompleted: false,
  ),
];

final mockWeeklyPlan = [
  const MockPlanItem(
    id: 'w1',
    title: 'Finish business plan draft',
    category: 'Career',
    dueDate: 'Friday',
    priority: 'high',
  ),
  const MockPlanItem(
    id: 'w2',
    title: 'Schedule mentor call',
    category: 'Career',
    dueDate: 'Wednesday',
  ),
  const MockPlanItem(
    id: 'w3',
    title: 'Complete online certification',
    category: 'Learning',
    dueDate: 'Sunday',
  ),
];

// ============================================
// NOTES
// ============================================

class MockNote {
  const MockNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.tags = const [],
    this.linkedIdol,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final List<String> tags;
  final String? linkedIdol;
}

final mockNotes = [
  MockNote(
    id: 'n1',
    title: 'Key learnings from Elon\'s biography',
    content: 'The most important thing I learned is the power of first principles thinking. Instead of following conventional wisdom, break problems down to their fundamental truths.',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    tags: ['Learning', 'Inspiration'],
    linkedIdol: 'Elon Musk',
  ),
  MockNote(
    id: 'n2',
    title: 'My 5-year career roadmap',
    content: 'Year 1: Build skills and network\nYear 2: Start side project\nYear 3: Validate and grow\nYear 4: Full-time transition\nYear 5: Scale or pivot',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    tags: ['Career', 'Planning'],
  ),
  MockNote(
    id: 'n3',
    title: 'Investment strategy notes',
    content: 'Focus on index funds for stability. Allocate 20% for high-growth tech stocks. Keep 6 months emergency fund.',
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
    tags: ['Finance'],
  ),
  MockNote(
    id: 'n4',
    title: 'Weekly reflection - Week 42',
    content: 'This week I made progress on my coding skills. Need to focus more on networking next week.',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    tags: ['Reflection'],
  ),
];

// ============================================
// CHAT MESSAGES
// ============================================

class MockMessage {
  const MockMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  });

  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
}

final mockChatMessages = [
  MockMessage(
    id: 'm1',
    content: 'Hi! I\'m your AI coach. I can help you track your progress, suggest actions, and answer questions about your idols. What would you like to work on today?',
    isUser: false,
    timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
  ),
  MockMessage(
    id: 'm2',
    content: 'I want to understand what Elon Musk was doing at my age.',
    isUser: true,
    timestamp: DateTime.now().subtract(const Duration(minutes: 28)),
  ),
  MockMessage(
    id: 'm3',
    content: 'At age 25, Elon Musk had just co-founded Zip2 with his brother. He was working intensely, sometimes sleeping at the office. Key things he focused on:\n\n• Learning web development\n• Building client relationships\n• Iterating rapidly on the product\n\nWould you like me to suggest specific actions you could take to follow a similar path?',
    isUser: false,
    timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
  ),
];

// ============================================
// USER PROFILE
// ============================================

class MockUserProfile {
  const MockUserProfile({
    required this.name,
    required this.email,
    required this.birthDate,
    this.avatarUrl,
    this.bio,
    this.interests = const [],
  });

  final String name;
  final String email;
  final DateTime birthDate;
  final String? avatarUrl;
  final String? bio;
  final List<String> interests;

  int get age {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }
}

final mockUserProfile = MockUserProfile(
  name: 'Alex Johnson',
  email: 'alex@example.com',
  birthDate: DateTime(1999, 5, 15),
  bio: 'Aspiring entrepreneur and lifelong learner.',
  interests: ['Technology', 'Startups', 'Finance', 'Leadership'],
);

// ============================================
// INTERESTS
// ============================================

const mockInterests = [
  'Technology',
  'Startups',
  'Finance',
  'Leadership',
  'Science',
  'Arts',
  'Sports',
  'Music',
  'Writing',
  'Design',
  'Marketing',
  'Health',
  'Philanthropy',
  'Education',
  'Innovation',
];

// ============================================
// ACHIEVEMENTS
// ============================================

class MockAchievement {
  const MockAchievement({
    required this.id,
    required this.title,
    required this.date,
    required this.category,
    this.description,
    this.evidence,
  });

  final String id;
  final String title;
  final DateTime date;
  final String category;
  final String? description;
  final String? evidence;
}

final mockAchievements = [
  MockAchievement(
    id: 'a1',
    title: 'Completed Python Certification',
    date: DateTime.now().subtract(const Duration(days: 30)),
    category: 'Learning',
    description: 'Finished the complete Python developer course on Udemy.',
  ),
  MockAchievement(
    id: 'a2',
    title: 'First 1000 users',
    date: DateTime.now().subtract(const Duration(days: 60)),
    category: 'Career',
    description: 'My side project reached 1000 active users.',
  ),
  MockAchievement(
    id: 'a3',
    title: 'Emergency fund complete',
    date: DateTime.now().subtract(const Duration(days: 90)),
    category: 'Finance',
    description: 'Saved 6 months of expenses.',
  ),
];

// ============================================
// NOTIFICATIONS
// ============================================

class MockNotification {
  const MockNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.type = 'info',
  });

  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String type;
}

final mockNotifications = [
  MockNotification(
    id: 'notif1',
    title: 'New milestone unlocked!',
    message: 'You\'ve reached 75% closeness in Learning category.',
    timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    type: 'achievement',
  ),
  MockNotification(
    id: 'notif2',
    title: 'Daily reminder',
    message: 'Don\'t forget to complete today\'s plan items.',
    timestamp: DateTime.now().subtract(const Duration(hours: 8)),
    type: 'reminder',
  ),
  MockNotification(
    id: 'notif3',
    title: 'Weekly summary ready',
    message: 'Check out your progress this week.',
    timestamp: DateTime.now().subtract(const Duration(days: 1)),
    isRead: true,
    type: 'info',
  ),
];
