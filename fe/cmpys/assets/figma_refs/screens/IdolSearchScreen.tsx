import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Search, TrendingUp, Users } from 'lucide-react';

interface IdolSearchScreenProps {
  onBack: () => void;
  onSelectIdol?: (idol: any) => void;
}

const trendingIdols = [
  { id: '1', name: 'Elon Musk', category: 'Entrepreneur', initials: 'EM' },
  { id: '2', name: 'Steve Jobs', category: 'Innovator', initials: 'SJ' },
  { id: '3', name: 'Warren Buffett', category: 'Investor', initials: 'WB' },
  { id: '4', name: 'Oprah Winfrey', category: 'Media', initials: 'OW' },
];

const categories = [
  'Business',
  'Technology',
  'Finance',
  'Entertainment',
  'Sports',
  'Science',
  'Politics',
  'Arts',
];

export function IdolSearchScreen({ onBack, onSelectIdol }: IdolSearchScreenProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);

  const handleSelectIdol = (idol: any) => {
    if (onSelectIdol) {
      onSelectIdol(idol);
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-4 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl mb-4">Search Idols</h1>

        {/* Search Field */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.4 }}
          className="relative"
        >
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-[#A1A1AA]" />
          <input
            type="text"
            placeholder="Search by name or profession..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] pl-12 pr-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-8 space-y-6">
        {/* Categories */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2, duration: 0.4 }}
            className="text-white font-medium mb-3 flex items-center gap-2"
          >
            <Users className="w-5 h-5 text-[#7B61FF]" />
            Categories
          </motion.h2>
          <div className="flex flex-wrap gap-2">
            {categories.map((category, idx) => (
              <motion.button
                key={category}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.3 + idx * 0.05, duration: 0.3 }}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() =>
                  setSelectedCategory(selectedCategory === category ? null : category)
                }
                className={`px-4 py-2 rounded-[14px] text-sm font-medium transition-all ${
                  selectedCategory === category
                    ? 'bg-[#7B61FF]/20 border-2 border-[#7B61FF] text-white'
                    : 'bg-[#1C1C1E] border border-[#2A2A2E] text-[#A1A1AA]'
                }`}
              >
                {category}
              </motion.button>
            ))}
          </div>
        </div>

        {/* Trending Idols */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5, duration: 0.4 }}
            className="text-white font-medium mb-3 flex items-center gap-2"
          >
            <TrendingUp className="w-5 h-5 text-[#7B61FF]" />
            Trending Idols
          </motion.h2>
          <div className="space-y-3">
            {trendingIdols.map((idol, idx) => (
              <motion.button
                key={idol.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.6 + idx * 0.05, duration: 0.4 }}
                whileHover={{ scale: 1.02, x: 4 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => handleSelectIdol(idol)}
                className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[20px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
              >
                <div className="w-12 h-12 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-lg shadow-[#7B61FF]/20 flex-shrink-0">
                  <span className="text-white font-medium">{idol.initials}</span>
                </div>
                <div className="flex-1 text-left min-w-0">
                  <h3 className="text-white font-medium truncate">{idol.name}</h3>
                  <p className="text-[#A1A1AA] text-sm">{idol.category}</p>
                </div>
                <div className="w-8 h-8 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center flex-shrink-0">
                  <span className="text-[#7B61FF] text-lg">+</span>
                </div>
              </motion.button>
            ))}
          </div>
        </div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.9, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            Search our database of successful individuals across industries. We continuously add new idols based on verified achievements and public data.
          </p>
        </motion.div>
      </div>
    </div>
  );
}
