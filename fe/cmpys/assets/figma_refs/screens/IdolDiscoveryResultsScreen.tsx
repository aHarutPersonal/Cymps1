import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, Search, AlertCircle } from 'lucide-react';
import { IdolCandidateCard } from '../IdolCandidateCard';
import { PrimaryButton } from '../PrimaryButton';

interface IdolDiscoveryResultsScreenProps {
  onBack: () => void;
  onImport?: () => void;
}

const mockCandidates = [
  {
    id: '1',
    name: 'Warren Buffett',
    description: 'American investor and philanthropist',
    birthDate: 'August 30, 1930',
    confidence: 97,
    provider: 'Wikipedia',
  },
  {
    id: '2',
    name: 'Warren Edward Buffett',
    description: 'CEO of Berkshire Hathaway',
    birthDate: '1930',
    confidence: 95,
    provider: 'Wikidata',
  },
  {
    id: '3',
    name: 'Warren Buffet',
    description: 'Business magnate and investor',
    birthDate: 'Aug 1930',
    confidence: 89,
    provider: 'Wikipedia',
  },
  {
    id: '4',
    name: 'Warren E. Buffett',
    description: 'Chairman and CEO of Berkshire Hathaway Inc.',
    birthDate: '1930-08-30',
    confidence: 92,
    provider: 'Wikidata',
  },
];

export function IdolDiscoveryResultsScreen({ onBack, onImport }: IdolDiscoveryResultsScreenProps) {
  const [searchQuery, setSearchQuery] = useState('Warren Buffett');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [candidates] = useState(mockCandidates);
  const [showEmpty, setShowEmpty] = useState(false);

  const handleSearch = () => {
    // In a real app, this would trigger a new search
    console.log('Searching for:', searchQuery);
  };

  const handleImport = () => {
    if (selectedId && onImport) {
      onImport();
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
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
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl mb-4">Search the web</h1>

        {/* Search Bar */}
        <div className="flex items-center gap-2">
          <div className="flex-1 flex items-center gap-3 bg-[#1C1C1E] rounded-[20px] px-4 py-3 border border-[#2A2A2E]">
            <Search className="w-5 h-5 text-[#A1A1AA]" />
            <input
              type="text"
              placeholder="Search for an idol..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyPress={handleKeyPress}
              className="flex-1 bg-transparent text-white placeholder-[#A1A1AA] outline-none"
            />
          </div>
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={handleSearch}
            className="w-12 h-12 rounded-[16px] bg-[#7B61FF] flex items-center justify-center flex-shrink-0"
          >
            <Search className="w-5 h-5 text-white" />
          </motion.button>
        </div>
      </motion.div>

      {/* Results List */}
      <div className="flex-1 overflow-y-auto px-6 py-6">
        <AnimatePresence mode="wait">
          {!showEmpty && candidates.length > 0 ? (
            <motion.div
              key="results"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="space-y-3"
            >
              {candidates.map((candidate, index) => (
                <motion.div
                  key={candidate.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.1, duration: 0.4 }}
                >
                  <IdolCandidateCard
                    {...candidate}
                    selected={selectedId === candidate.id}
                    onClick={() => setSelectedId(candidate.id)}
                  />
                </motion.div>
              ))}
            </motion.div>
          ) : (
            <motion.div
              key="empty"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ duration: 0.5 }}
              className="flex flex-col items-center justify-center h-full text-center px-8"
            >
              <motion.div
                animate={{
                  y: [0, -10, 0],
                }}
                transition={{
                  type: 'tween',
                  duration: 2,
                  repeat: Infinity,
                  ease: 'easeInOut',
                }}
                className="w-16 h-16 rounded-full bg-[#1C1C1E] border border-[#2A2A2E] flex items-center justify-center mb-6"
              >
                <AlertCircle className="w-8 h-8 text-[#7B61FF]" />
              </motion.div>
              
              <h3 className="text-white text-xl mb-3">No results found</h3>
              <p className="text-[#A1A1AA] mb-6">
                We couldn't find any matches for your search.
              </p>
              
              <div className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] w-full">
                <p className="text-white text-sm font-medium mb-3">Tips for better results:</p>
                <ul className="text-[#A1A1AA] text-sm text-left space-y-2">
                  <li className="flex items-start gap-2">
                    <span className="text-[#7B61FF] mt-1">•</span>
                    <span>Try using the person's full name</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-[#7B61FF] mt-1">•</span>
                    <span>Check for spelling mistakes</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-[#7B61FF] mt-1">•</span>
                    <span>Include their profession or field</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-[#7B61FF] mt-1">•</span>
                    <span>Use alternative name variations</span>
                  </li>
                </ul>
              </div>

              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => setShowEmpty(false)}
                className="mt-6 px-6 py-3 rounded-full bg-[#1C1C1E] text-[#7B61FF] border border-[#7B61FF]/30"
              >
                Try another search
              </motion.button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Bottom CTA */}
      {!showEmpty && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="px-6 py-4 pb-24 border-t border-[#2A2A2E] bg-[#121212]"
        >
          <PrimaryButton onClick={handleImport} disabled={!selectedId}>
            Import selected idol
          </PrimaryButton>
        </motion.div>
      )}

      {/* Toggle button for demo purposes */}
      <motion.button
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        onClick={() => setShowEmpty(!showEmpty)}
        className="fixed bottom-32 right-6 px-4 py-2 rounded-full bg-[#7B61FF]/20 text-[#7B61FF] text-xs border border-[#7B61FF]/30 backdrop-blur-lg"
      >
        Toggle Empty State
      </motion.button>
    </div>
  );
}