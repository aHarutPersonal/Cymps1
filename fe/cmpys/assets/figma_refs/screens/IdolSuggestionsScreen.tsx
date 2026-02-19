import React, { useState } from 'react';
import { motion } from 'motion/react';
import { PrimaryButton } from '../PrimaryButton';
import { IdolCard } from '../IdolCard';
import { ChevronLeft, Search } from 'lucide-react';

interface IdolSuggestionsScreenProps {
  onContinue: () => void;
  onBack: () => void;
}

const idols = [
  { name: 'Elon Musk', domain: 'Entrepreneurship', match: 92 },
  { name: 'Steve Jobs', domain: 'Innovation', match: 88 },
  { name: 'Warren Buffett', domain: 'Finance', match: 85 },
  { name: 'Oprah Winfrey', domain: 'Media', match: 82 },
  { name: 'Bill Gates', domain: 'Technology', match: 79 },
];

export function IdolSuggestionsScreen({ onContinue, onBack }: IdolSuggestionsScreenProps) {
  const [searchTerm, setSearchTerm] = useState('');

  const filteredIdols = idols.filter(idol =>
    idol.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    idol.domain.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      <motion.div
        initial={{ opacity: 0, x: -20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.3 }}
        className="p-6 pb-0"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
      </motion.div>
      <div className="flex-1 px-6 pt-8 pb-6 flex flex-col">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="mb-8"
        >
          <h1 className="text-white text-3xl mb-2">Choose your idols</h1>
          <p className="text-[#A1A1AA]">Based on your focus areas</p>
        </motion.div>

        {/* Search Bar */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="mb-6"
        >
          <div className="flex items-center gap-3 bg-[#1C1C1E] rounded-[20px] px-4 py-3 border border-[#2A2A2E]">
            <Search className="w-5 h-5 text-[#A1A1AA]" />
            <input
              type="text"
              placeholder="Search idols..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="flex-1 bg-transparent text-white placeholder-[#A1A1AA] outline-none"
            />
          </div>
        </motion.div>

        <div className="flex-1 overflow-y-auto space-y-3">
          {filteredIdols.length > 0 ? (
            filteredIdols.map((idol, index) => (
              <motion.div
                key={idol.name}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: index * 0.1, duration: 0.5 }}
              >
                <IdolCard {...idol} />
              </motion.div>
            ))
          ) : (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5 }}
              className="text-center py-12"
            >
              <p className="text-[#A1A1AA] mb-2">No idols found</p>
              <p className="text-[#A1A1AA] text-sm">Try a different search term</p>
            </motion.div>
          )}
        </div>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.5 }}
          className="pt-6"
        >
          <PrimaryButton onClick={onContinue}>Continue</PrimaryButton>
        </motion.div>
      </div>
    </div>
  );
}