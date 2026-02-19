import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, Search, Sparkles, Copy, CheckCircle2, Clock, XCircle, AlertCircle } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface TimelineEnrichmentScreenProps {
  onBack: () => void;
  onViewPartial?: () => void;
  onRetry?: () => void;
  onChangeIdol?: () => void;
  variant?: 'running' | 'partial' | 'failed';
}

interface Step {
  id: string;
  label: string;
  status: 'done' | 'in-progress' | 'pending';
  icon: React.ReactNode;
}

export function TimelineEnrichmentScreen({ 
  onBack, 
  onViewPartial, 
  onRetry, 
  onChangeIdol,
  variant = 'running' 
}: TimelineEnrichmentScreenProps) {
  const [currentVariant, setCurrentVariant] = useState<'running' | 'partial' | 'failed'>(variant);
  const [progress, setProgress] = useState(currentVariant === 'running' ? 45 : currentVariant === 'partial' ? 65 : 30);

  // Simulate progress for running variant
  useEffect(() => {
    if (currentVariant === 'running') {
      const interval = setInterval(() => {
        setProgress(prev => {
          if (prev >= 90) return 45; // Loop back for demo
          return prev + 1;
        });
      }, 150);
      return () => clearInterval(interval);
    }
  }, [currentVariant]);

  // Update progress when variant changes
  useEffect(() => {
    if (currentVariant === 'running') {
      setProgress(45);
    } else if (currentVariant === 'partial') {
      setProgress(65);
    } else {
      setProgress(30);
    }
  }, [currentVariant]);

  const getSteps = (): Step[] => {
    if (currentVariant === 'failed') {
      return [
        {
          id: '1',
          label: 'Finding sources',
          status: 'done',
          icon: <Search className="w-5 h-5" />,
        },
        {
          id: '2',
          label: 'Extracting achievements',
          status: 'in-progress',
          icon: <Sparkles className="w-5 h-5" />,
        },
        {
          id: '3',
          label: 'Deduplicating timeline',
          status: 'pending',
          icon: <Copy className="w-5 h-5" />,
        },
        {
          id: '4',
          label: 'Finalizing',
          status: 'pending',
          icon: <CheckCircle2 className="w-5 h-5" />,
        },
      ];
    }

    if (currentVariant === 'partial') {
      return [
        {
          id: '1',
          label: 'Finding sources',
          status: 'done',
          icon: <Search className="w-5 h-5" />,
        },
        {
          id: '2',
          label: 'Extracting achievements',
          status: 'done',
          icon: <Sparkles className="w-5 h-5" />,
        },
        {
          id: '3',
          label: 'Deduplicating timeline',
          status: 'in-progress',
          icon: <Copy className="w-5 h-5" />,
        },
        {
          id: '4',
          label: 'Finalizing',
          status: 'pending',
          icon: <CheckCircle2 className="w-5 h-5" />,
        },
      ];
    }

    // running variant
    return [
      {
        id: '1',
        label: 'Finding sources',
        status: 'done',
        icon: <Search className="w-5 h-5" />,
      },
      {
        id: '2',
        label: 'Extracting achievements',
        status: 'in-progress',
        icon: <Sparkles className="w-5 h-5" />,
      },
      {
        id: '3',
        label: 'Deduplicating timeline',
        status: 'pending',
        icon: <Copy className="w-5 h-5" />,
      },
      {
        id: '4',
        label: 'Finalizing',
        status: 'pending',
        icon: <CheckCircle2 className="w-5 h-5" />,
      },
    ];
  };

  const steps = getSteps();

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'done':
        return 'text-[#7B61FF]';
      case 'in-progress':
        return 'text-[#7B61FF]';
      case 'pending':
        return 'text-[#A1A1AA]';
      default:
        return 'text-[#A1A1AA]';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'done':
        return <CheckCircle2 className="w-5 h-5 text-[#7B61FF]" />;
      case 'in-progress':
        return (
          <motion.div
            animate={{ rotate: 360 }}
            transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
          >
            <Clock className="w-5 h-5 text-[#7B61FF]" />
          </motion.div>
        );
      case 'pending':
        return <Clock className="w-5 h-5 text-[#A1A1AA]" />;
      default:
        return null;
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
        <h1 className="text-white text-2xl">Building your idol timeline</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6">
        {/* Progress Bar */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="mb-8"
        >
          <div className="flex items-center justify-between mb-3">
            <span className="text-[#A1A1AA] text-sm">Progress</span>
            <motion.span
              key={progress}
              initial={{ scale: 1.2, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className="text-[#7B61FF] font-medium"
            >
              {progress}%
            </motion.span>
          </div>
          <div className="h-3 bg-[#1C1C1E] rounded-full border border-[#2A2A2E] overflow-hidden">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${progress}%` }}
              transition={{ duration: 0.5, ease: 'easeOut' }}
              className="h-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] relative"
            >
              <motion.div
                animate={{
                  x: ['0%', '100%'],
                }}
                transition={{
                  duration: 1.5,
                  repeat: Infinity,
                  ease: 'linear',
                }}
                className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
              />
            </motion.div>
          </div>
        </motion.div>

        {/* Steps List */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E] mb-6"
        >
          <div className="space-y-4">
            {steps.map((step, index) => (
              <motion.div
                key={step.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.3 + index * 0.1, duration: 0.4 }}
                className="flex items-center gap-4"
              >
                <div
                  className={`flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center ${
                    step.status === 'done'
                      ? 'bg-[#7B61FF]/20 border border-[#7B61FF]/30'
                      : step.status === 'in-progress'
                      ? 'bg-[#7B61FF]/20 border border-[#7B61FF]/30'
                      : 'bg-[#1C1C1E] border border-[#2A2A2E]'
                  }`}
                >
                  <div className={getStatusColor(step.status)}>{step.icon}</div>
                </div>
                <div className="flex-1">
                  <p className={`${step.status === 'pending' ? 'text-[#A1A1AA]' : 'text-white'}`}>
                    {step.label}
                  </p>
                </div>
                <div className="flex-shrink-0">{getStatusIcon(step.status)}</div>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Helper Text */}
        {currentVariant === 'running' && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.6, duration: 0.5 }}
            className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] mb-6"
          >
            <p className="text-[#A1A1AA] text-sm text-center">
              You can continue using CMPYS while we enrich data.
            </p>
          </motion.div>
        )}

        {/* Partial Ready Card */}
        <AnimatePresence>
          {currentVariant === 'partial' && (
            <motion.div
              initial={{ opacity: 0, y: 20, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 20, scale: 0.95 }}
              transition={{ delay: 0.6, duration: 0.5 }}
              className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#7B61FF]/30 mb-6"
            >
              <div className="flex gap-3 mb-4">
                <div className="flex-shrink-0">
                  <div className="w-12 h-12 rounded-full bg-[#7B61FF]/20 flex items-center justify-center">
                    <Sparkles className="w-6 h-6 text-[#7B61FF]" />
                  </div>
                </div>
                <div className="flex-1">
                  <h3 className="text-white font-medium mb-2">Partial timeline ready</h3>
                  <p className="text-[#A1A1AA] text-sm">
                    Some achievements are available now. We'll continue enriching the rest in the background.
                  </p>
                </div>
              </div>
              <PrimaryButton onClick={onViewPartial}>View partial timeline</PrimaryButton>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Failed Card */}
        <AnimatePresence>
          {currentVariant === 'failed' && (
            <motion.div
              initial={{ opacity: 0, y: 20, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 20, scale: 0.95 }}
              transition={{ delay: 0.6, duration: 0.5 }}
              className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#FF6B6B]/30 mb-6"
            >
              <div className="flex gap-3 mb-6">
                <div className="flex-shrink-0">
                  <div className="w-12 h-12 rounded-full bg-[#FF6B6B]/20 flex items-center justify-center">
                    <XCircle className="w-6 h-6 text-[#FF6B6B]" />
                  </div>
                </div>
                <div className="flex-1">
                  <h3 className="text-white font-medium mb-2">Enrichment failed</h3>
                  <p className="text-[#A1A1AA] text-sm">
                    We encountered an issue while extracting achievements. This might be due to limited source data or connectivity issues.
                  </p>
                </div>
              </div>
              <div className="space-y-3">
                <PrimaryButton onClick={onRetry}>Retry enrichment</PrimaryButton>
                <motion.button
                  onClick={onChangeIdol}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="w-full px-6 py-4 rounded-[20px] bg-transparent text-[#7B61FF] border-2 border-[#7B61FF]/30 transition-all hover:border-[#7B61FF]/50 hover:bg-[#7B61FF]/5"
                >
                  Change idol
                </motion.button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Info Helper Text (for all variants) */}
        {currentVariant !== 'failed' && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.8, duration: 0.5 }}
            className="flex items-start gap-3 bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
          >
            <AlertCircle className="w-5 h-5 text-[#7B61FF] flex-shrink-0 mt-0.5" />
            <p className="text-[#A1A1AA] text-sm">
              You can continue using CMPYS while we enrich data.
            </p>
          </motion.div>
        )}
      </div>

      {/* Variant Toggle (for demo) */}
      <div className="absolute bottom-32 right-6 bg-[#1C1C1E] rounded-[20px] p-3 border border-[#2A2A2E] shadow-xl">
        <p className="text-[#A1A1AA] text-xs mb-2 text-center">Variant</p>
        <div className="flex flex-col gap-2">
          {(['running', 'partial', 'failed'] as const).map((v) => (
            <motion.button
              key={v}
              onClick={() => setCurrentVariant(v)}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              className={`px-3 py-1 rounded-full text-xs border transition-all ${
                currentVariant === v
                  ? 'bg-[#7B61FF] text-white border-[#7B61FF]'
                  : 'bg-transparent text-[#A1A1AA] border-[#2A2A2E] hover:border-[#7B61FF]/30'
              }`}
            >
              {v.charAt(0).toUpperCase() + v.slice(1)}
            </motion.button>
          ))}
        </div>
      </div>
    </div>
  );
}