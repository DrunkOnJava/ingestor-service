/**
 * Mock implementation of Claude API for testing
 */

import { Entity, EntityExtractionResult, EntityType } from '../../core/entity/types';

/**
 * Creates a mock Claude API service for testing
 * This mock simulates Claude's entity extraction capabilities
 */
export function createClaudeMock() {
  // Sample entities that can be "extracted" from test content
  const sampleEntities: Record<string, Entity[]> = {
    default: [
      {
        name: 'John Doe',
        type: EntityType.PERSON,
        mentions: [{ context: 'John Doe is CEO', position: 0, relevance: 0.9 }]
      },
      {
        name: 'Acme Corporation',
        type: EntityType.ORGANIZATION,
        mentions: [{ context: 'works at Acme Corporation', position: 10, relevance: 0.8 }]
      },
      {
        name: 'New York',
        type: EntityType.LOCATION,
        mentions: [{ context: 'based in New York', position: 30, relevance: 0.7 }]
      }
    ],
    
    meeting: [
      {
        name: 'Quarterly Review',
        type: EntityType.EVENT,
        mentions: [{ context: 'Quarterly Review meeting', position: 0, relevance: 0.95 }]
      },
      {
        name: 'Jane Smith',
        type: EntityType.PERSON,
        mentions: [{ context: 'Jane Smith will present', position: 20, relevance: 0.9 }]
      },
      {
        name: '2023-05-15',
        type: EntityType.DATE,
        mentions: [{ context: 'scheduled for May 15, 2023', position: 40, relevance: 0.8 }]
      },
      {
        name: 'Marketing Department',
        type: EntityType.ORGANIZATION,
        mentions: [{ context: 'the Marketing Department', position: 60, relevance: 0.7 }]
      }
    ],
    
    technical: [
      {
        name: 'Machine Learning',
        type: EntityType.TECHNOLOGY,
        mentions: [{ context: 'using Machine Learning algorithms', position: 5, relevance: 0.9 }]
      },
      {
        name: 'TensorFlow',
        type: EntityType.TECHNOLOGY,
        mentions: [{ context: 'implemented in TensorFlow', position: 30, relevance: 0.85 }]
      },
      {
        name: 'Smith et al.',
        type: EntityType.PERSON,
        mentions: [{ context: 'as described by Smith et al.', position: 50, relevance: 0.6 }]
      },
      {
        name: '2022-11-01',
        type: EntityType.DATE, 
        mentions: [{ context: 'published on November 1, 2022', position: 70, relevance: 0.7 }]
      }
    ],
    
    // Empty result for testing error cases
    empty: []
  };
  
  /**
   * Mock Claude completion function
   */
  const completion = jest.fn(async (options: {
    prompt: string;
    model?: string;
    maxTokens?: number;
    temperature?: number;
  }) => {
    // Simple content-based routing for different mock entity sets
    let entitySet = 'default';
    
    const prompt = options.prompt.toLowerCase();
    
    if (prompt.includes('meeting') || prompt.includes('schedule')) {
      entitySet = 'meeting';
    } else if (prompt.includes('algorithm') || prompt.includes('technical') || prompt.includes('technology')) {
      entitySet = 'technical';
    } else if (prompt.includes('error') || prompt.includes('empty')) {
      entitySet = 'empty';
    }
    
    const entities = sampleEntities[entitySet] || [];
    
    // Simulate processing delay
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Simulate potential errors
    if (prompt.includes('error') || options.model === 'error') {
      throw new Error('Claude API error: Failed to complete the request');
    }
    
    // Return a simulated Claude response
    return {
      completion: JSON.stringify({ entities }),
      stop_reason: 'end_turn',
      model: options.model || 'claude-3-haiku-20240307'
    };
  });
  
  /**
   * Mock entity extraction function
   */
  const extractEntities = jest.fn(async (
    content: string,
    options: { model?: string; confidenceThreshold?: number } = {}
  ): Promise<EntityExtractionResult> => {
    try {
      // Build a prompt that would be sent to Claude
      const prompt = `Extract entities from the following content: ${content}`;
      
      const response = await completion({
        prompt,
        model: options.model || 'claude-3-haiku-20240307',
        maxTokens: 1000,
        temperature: 0
      });
      
      // Parse the entities from the response
      const result = JSON.parse(response.completion);
      
      // Apply confidence threshold if specified
      let entities = result.entities || [];
      if (options.confidenceThreshold && options.confidenceThreshold > 0) {
        entities = entities.filter(entity => {
          // Get the maximum relevance from mentions
          const maxRelevance = Math.max(...entity.mentions.map(m => m.relevance || 0));
          return maxRelevance >= options.confidenceThreshold;
        });
      }
      
      return {
        entities,
        success: true,
        model: response.model
      };
    } catch (error) {
      return {
        entities: [],
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  });
  
  return {
    completion,
    extractEntities
  };
}