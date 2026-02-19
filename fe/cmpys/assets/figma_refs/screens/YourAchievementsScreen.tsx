import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, Filter, Plus, Briefcase, GraduationCap, DollarSign, Heart, Brain, Calendar } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface YourAchievementsScreenProps {
  onBack: () => void;
  onAddAchievement: () => void;
}

type Category = 'All' | 'Career' | 'Learning' | 'Finance' | 'Impact' | 'Mindset';

interface Achievement {
  id: string;
  title: string;
  date: string;
  category: Exclude<Category, 'All'>;
  notes?: string;
}

const categories: { id: Category; label: string; icon?: React.ReactNode }[] = [
  { id: 'All', label: 'All' },
  { id: 'Career', label: 'Career', icon: <Briefcase className="w-3 h-3" /> },
  { id: 'Learning', label: 'Learning', icon: <GraduationCap className="w-3 h-3" /> },
  { id: 'Finance', label: 'Finance', icon: <DollarSign className="w-3 h-3" /> },
  { id: 'Impact', label: 'Impact', icon: <Heart className="w-3 h-3" /> },
  { id: 'Mindset', label: 'Mindset', icon: <Brain className="w-3 h-3" /> },
];

// Mock data
const mockAchievements: Achievement[] = [
  {
    id: '1',
    title: 'Founded first startup',
    date: '2024-03-15',
    category: 'Career',
    notes: 'Launched an AI-powered productivity tool',
  },
  {
    id: '2',
    title: 'Completed Machine Learning course',
    date: '2024-02-10',
    category: 'Learning',
  },
  {
    id: '3',
    title: 'Reached $100K annual revenue',
    date: '2024-01-20',
    category: 'Finance',
  },
  {
    id: '4',
    title: 'Mentored 5 junior developers',
    date: '2023-11-05',
    category: 'Impact',
  },
  {
    id: '5',
    title: 'Established daily meditation practice',
    date: '2023-09-12',
    category: 'Mindset',
  },
  {
    id: '6',
    title: 'Promoted to Senior Engineer',
    date: '2023-06-01',
    category: 'Career',
  },
  {
    id: '7',
    title: 'Published first technical article',
    date: '2023-03-18',
    category: 'Learning',
  },
];

const getCategoryIcon = (category: Exclude<Category, 'All'>) => {
  const icons = {
    Career: <Briefcase className="w-3 h-3" />,
    Learning: <GraduationCap className="w-3 h-3" />,
    Finance: <DollarSign className="w-3 h-3" />,
    Impact: <Heart className="w-3 h-3" />,
    Mindset: <Brain className="w-3 h-3" />,
  };
  return icons[category];
};

export function YourAchievementsScreen({ onBack, onAddAchievement }: YourAchievementsScreenProps) {
  const [selectedCategory, setSelectedCategory] = useState<Category>('All');
  const [hasAchievements] = useState(true); // Set to false to see empty state

  // Filter achievements by category
  const filteredAchievements = selectedCategory === 'All'
    ? mockAchievements
    : mockAchievements.filter(a => a.category === selectedCategory);

  // Group achievements by year
  const groupedByYear = filteredAchievements.reduce((acc, achievement) => {
    const year = new Date(achievement.date).getFullYear().toString();
    if (!acc[year]) {
      acc[year] = [];
    }
    acc[year].push(achievement);
    return acc;
  }, {} as Record<string, Achievement[]>);

  // Sort years descending
  const sortedYears = Object.keys(groupedByYear).sort((a, b) => parseInt(b) - parseInt(a));

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <div className="flex items-center justify-between mb-4">
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onBack}
            className="p-2 -ml-2"
          >
            <ChevronLeft className="w-6 h-6 text-white" />
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            className="p-2 -mr-2"
          >
            <Filter className="w-6 h-6 text-[#A1A1AA]" />
          </motion.button>
        </div>
        <h1 className="text-white text-2xl">Your achievements</h1>
      </motion.div>

      {/* Category Chips */}
      {hasAchievements && (
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="px-6 py-4 border-b border-[#2A2A2E] bg-[#121212]"
        >
          <div className="flex gap-2 overflow-x-auto scrollbar-hide pb-1">
            {categories.map((category) => (
              <motion.button
                key={category.id}
                onClick={() => setSelectedCategory(category.id)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className={`flex items-center gap-1.5 px-4 py-2 rounded-full border transition-all whitespace-nowrap flex-shrink-0 ${
                  selectedCategory === category.id
                    ? 'bg-[#7B61FF] border-[#7B61FF] text-white'
                    : 'bg-[#1C1C1E] border-[#2A2A2E] text-[#A1A1AA] hover:border-[#7B61FF]/30'
                }`}
              >
                {category.icon}
                <span className="text-sm">{category.label}</span>
              </motion.button>
            ))}
          </div>
        </motion.div>
      )}

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-24">
        {!hasAchievements || filteredAchievements.length === 0 ? (
          /* Empty State */
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.2, duration: 0.5 }}
            className="flex flex-col items-center justify-center h-full"
          >
            <motion.div
              animate={{
                scale: [1, 1.05, 1],
              }}
              transition={{
                duration: 3,
                repeat: Infinity,
                ease: 'easeInOut',
              }}
              className="w-24 h-24 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center mb-6 shadow-2xl shadow-[#7B61FF]/20"
            >
              <Plus className="w-12 h-12 text-white" />
            </motion.div>
            <h2 className="text-white text-xl mb-3">
              {selectedCategory === 'All' ? 'No achievements yet' : `No ${selectedCategory.toLowerCase()} achievements`}
            </h2>
            <p className="text-[#A1A1AA] text-center mb-8 max-w-xs">
              {selectedCategory === 'All'
                ? 'Start tracking your journey by adding your first achievement'
                : `Add your first ${selectedCategory.toLowerCase()} achievement to get started`}
            </p>
            <PrimaryButton onClick={onAddAchievement}>
              Add your first achievement
            </PrimaryButton>
          </motion.div>
        ) : (
          /* Timeline List */
          <div className="space-y-8">
            {sortedYears.map((year, yearIndex) => (
              <motion.div
                key={year}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.2 + yearIndex * 0.1, duration: 0.5 }}
              >
                {/* Year Header */}
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center">
                    <span className="text-[#7B61FF] font-medium text-sm">{year}</span>
                  </div>
                  <div className="flex-1 h-px bg-gradient-to-r from-[#2A2A2E] to-transparent" />
                </div>

                {/* Achievement Cards */}
                <div className="space-y-3 ml-5 border-l-2 border-[#2A2A2E] pl-5">
                  {groupedByYear[year].map((achievement, index) => (
                    <motion.div
                      key={achievement.id}
                      initial={{ opacity: 0, x: -20 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.3 + yearIndex * 0.1 + index * 0.05, duration: 0.4 }}
                      whileHover={{ scale: 1.02, x: 4 }}
                      className="relative"
                    >
                      {/* Timeline Dot */}
                      <div className="absolute -left-[29px] top-5 w-3 h-3 rounded-full bg-[#7B61FF] border-2 border-[#121212]" />

                      {/* Card */}
                      <div className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all cursor-pointer">
                        <div className="flex items-start justify-between gap-3 mb-3">
                          <h3 className="text-white flex-1">{achievement.title}</h3>
                          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex-shrink-0">
                            {getCategoryIcon(achievement.category)}
                            <span className="text-[#7B61FF] text-xs">{achievement.category}</span>
                          </div>
                        </div>
                        <div className="flex items-center gap-2 text-[#A1A1AA] text-sm">
                          <Calendar className="w-4 h-4" />
                          <span>{formatDate(achievement.date)}</span>
                        </div>
                        {achievement.notes && (
                          <p className="text-[#A1A1AA] text-sm mt-2 line-clamp-2">
                            {achievement.notes}
                          </p>
                        )}
                      </div>
                    </motion.div>
                  ))}
                </div>
              </motion.div>
            ))}
          </div>
        )}
      </div>

      {/* Floating Action Button */}
      {hasAchievements && filteredAchievements.length > 0 && (
        <motion.button
          initial={{ opacity: 0, scale: 0 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.8, type: 'spring', stiffness: 300, damping: 20 }}
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onAddAchievement}
          className="fixed bottom-8 right-6 w-14 h-14 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] shadow-2xl shadow-[#7B61FF]/40 flex items-center justify-center"
          style={{ maxWidth: '390px', margin: '0 auto' }}
        >
          <Plus className="w-6 h-6 text-white" />
        </motion.button>
      )}

      {/* Achievement Count Badge */}
      {hasAchievements && filteredAchievements.length > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.5 }}
          className="absolute top-[168px] right-6 px-3 py-1.5 rounded-full bg-[#1C1C1E] border border-[#2A2A2E]"
        >
          <span className="text-[#7B61FF] text-xs font-medium">
            {filteredAchievements.length} {filteredAchievements.length === 1 ? 'achievement' : 'achievements'}
          </span>
        </motion.div>
      )}
    </div>
  );
}
