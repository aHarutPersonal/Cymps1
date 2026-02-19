import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Info } from 'lucide-react';
import { EvidenceSheet } from '../EvidenceSheet';
import { PrimaryButton } from '../PrimaryButton';

interface EvidenceSheetDemoScreenProps {
  onBack: () => void;
}

export function EvidenceSheetDemoScreen({ onBack }: EvidenceSheetDemoScreenProps) {
  const [isSheetOpen, setIsSheetOpen] = useState(false);
  const [selectedExample, setSelectedExample] = useState<'high' | 'medium' | 'low'>('high');

  const examples = {
    high: {
      title: 'Founded Berkshire Hathaway',
      category: 'Career' as const,
      confidence: 'High' as const,
      datePrecision: 'Exact date: May 10, 1965',
      sources: [
        {
          id: '1',
          url: 'https://en.wikipedia.org/wiki/Berkshire_Hathaway',
          title: 'Berkshire Hathaway - Wikipedia',
          snippet: 'Berkshire Hathaway Inc. is an American multinational conglomerate holding company headquartered in Omaha, Nebraska, United States. Founded in 1839 as a textile manufacturer, it transitioned to a holding company under Warren Buffett in 1965.',
        },
        {
          id: '2',
          url: 'https://www.berkshirehathaway.com/letters/1965ltr.html',
          title: 'Warren Buffett\'s 1965 Letter to Shareholders',
          snippet: 'In 1965, Berkshire Fine Spinning Associates and Hathaway Manufacturing Company merged to form Berkshire Hathaway. That same year, Warren Buffett\'s investment partnership began acquiring stock and eventually took control of the company.',
        },
        {
          id: '3',
          url: 'https://www.forbes.com/companies/berkshire-hathaway',
          title: 'Berkshire Hathaway - Forbes',
          snippet: 'Warren Buffett took over as CEO of Berkshire Hathaway in 1965, transforming the struggling textile company into one of the world\'s largest and most successful conglomerates.',
        },
      ],
    },
    medium: {
      title: 'First stock market investment',
      category: 'Finance' as const,
      confidence: 'Medium' as const,
      datePrecision: 'Approximate: Early 1942',
      sources: [
        {
          id: '1',
          url: 'https://www.biography.com/business-leaders/warren-buffett',
          title: 'Warren Buffett Biography',
          snippet: 'At age 11, Buffett bought his first stock, purchasing three shares of Cities Service Preferred. The exact date is not documented in official records, but it occurred in 1942.',
        },
        {
          id: '2',
          url: 'https://www.cnbc.com/warren-buffett-biography',
          title: 'Warren Buffett: Early Years - CNBC',
          snippet: 'Buffett made his first stock purchase around 1942 when he was approximately 11 years old, buying shares of Cities Service Preferred at $38 per share.',
        },
      ],
    },
    low: {
      title: 'Started first business venture',
      category: 'Career' as const,
      confidence: 'Low' as const,
      datePrecision: 'Estimated: Mid-1940s (childhood)',
      sources: [
        {
          id: '1',
          url: 'https://www.investopedia.com/young-warren-buffett',
          title: 'Young Warren Buffett - Investopedia',
          snippet: 'During his childhood in the 1940s, Buffett engaged in various entrepreneurial activities including selling gum, Coca-Cola bottles, and delivering newspapers. Specific dates for these early ventures are not well documented.',
        },
      ],
    },
  };

  const currentExample = examples[selectedExample];

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
        <h1 className="text-white text-2xl">Evidence Sheet Demo</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6">
        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] mb-6"
        >
          <div className="flex gap-3">
            <Info className="w-5 h-5 text-[#7B61FF] flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-[#A1A1AA] text-sm leading-relaxed">
                The Evidence Sheet is a reusable bottom sheet component that displays achievement verification details, source confidence, and references.
              </p>
            </div>
          </div>
        </motion.div>

        {/* Example Selection */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="mb-6"
        >
          <h3 className="text-white text-sm mb-3">Select confidence level</h3>
          <div className="flex gap-2">
            {(['high', 'medium', 'low'] as const).map((level) => (
              <motion.button
                key={level}
                onClick={() => setSelectedExample(level)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className={`flex-1 px-4 py-3 rounded-[16px] border-2 transition-all capitalize ${
                  selectedExample === level
                    ? 'bg-[#7B61FF] border-[#7B61FF] text-white'
                    : 'bg-[#1C1C1E] border-[#2A2A2E] text-[#A1A1AA] hover:border-[#7B61FF]/30'
                }`}
              >
                {level}
              </motion.button>
            ))}
          </div>
        </motion.div>

        {/* Achievement Preview */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] mb-6"
        >
          <h3 className="text-white mb-2">{currentExample.title}</h3>
          <div className="flex items-center gap-2 mb-4">
            <span className="text-[#A1A1AA] text-sm">{currentExample.category}</span>
            <span className="text-[#2A2A2E]">•</span>
            <span className="text-[#A1A1AA] text-sm">{currentExample.confidence} confidence</span>
          </div>
          <p className="text-[#A1A1AA] text-sm mb-4">
            {currentExample.sources.length} {currentExample.sources.length === 1 ? 'source' : 'sources'} available
          </p>
          <PrimaryButton onClick={() => setIsSheetOpen(true)}>
            View evidence details
          </PrimaryButton>
        </motion.div>

        {/* Features List */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E]"
        >
          <h3 className="text-white mb-4">Component features</h3>
          <div className="space-y-3">
            {[
              'Smooth slide-up animation',
              'Backdrop overlay with blur',
              'Achievement details card',
              'Confidence badge with color coding',
              'Source list with snippets',
              'Date precision indicator',
              'Open source buttons',
              'Report issue action',
              'Drag handle indicator',
              'Responsive scrolling',
            ].map((feature, index) => (
              <div key={index} className="flex items-center gap-3">
                <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                <span className="text-[#A1A1AA] text-sm">{feature}</span>
              </div>
            ))}
          </div>
        </motion.div>
      </div>

      {/* Evidence Sheet */}
      <EvidenceSheet
        isOpen={isSheetOpen}
        onClose={() => setIsSheetOpen(false)}
        achievement={currentExample}
        onOpenSource={(url) => {
          console.log('Opening source:', url);
          // In a real app, this would open the URL
        }}
        onReportIssue={() => {
          console.log('Report issue clicked');
          setIsSheetOpen(false);
          // In a real app, this would open a report form
        }}
      />
    </div>
  );
}
