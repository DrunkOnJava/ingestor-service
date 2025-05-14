/**
 * Tests for the Claude mock service
 */

import { createClaudeMock } from './claude-mock';
import { EntityType } from '../../core/entity/types';

describe('Claude Mock Service', () => {
  let claudeMock: ReturnType<typeof createClaudeMock>;
  
  beforeEach(() => {
    claudeMock = createClaudeMock();
  });
  
  afterEach(() => {
    jest.clearAllMocks();
  });
  
  describe('completion', () => {
    it('should return different entities based on prompt content', async () => {
      // Test default entities
      const defaultResponse = await claudeMock.completion({
        prompt: 'Extract entities from this general content',
      });
      
      const defaultResult = JSON.parse(defaultResponse.completion);
      expect(defaultResult.entities).toHaveLength(3);
      expect(defaultResult.entities[0].name).toBe('John Doe');
      
      // Test meeting entities
      const meetingResponse = await claudeMock.completion({
        prompt: 'Extract entities from this meeting schedule',
      });
      
      const meetingResult = JSON.parse(meetingResponse.completion);
      expect(meetingResult.entities).toHaveLength(4);
      expect(meetingResult.entities[0].name).toBe('Quarterly Review');
      
      // Test technical entities
      const technicalResponse = await claudeMock.completion({
        prompt: 'Extract entities from this technical document about algorithms',
      });
      
      const technicalResult = JSON.parse(technicalResponse.completion);
      expect(technicalResult.entities).toHaveLength(4);
      expect(technicalResult.entities[0].name).toBe('Machine Learning');
    });
    
    it('should throw an error when prompted with error keywords', async () => {
      await expect(
        claudeMock.completion({
          prompt: 'This should trigger an error',
          model: 'error'
        })
      ).rejects.toThrow('Claude API error');
    });
    
    it('should return empty entities when prompted with empty keywords', async () => {
      const response = await claudeMock.completion({
        prompt: 'Extract entities but return empty results',
      });
      
      const result = JSON.parse(response.completion);
      expect(result.entities).toHaveLength(0);
    });
  });
  
  describe('extractEntities', () => {
    it('should extract entities from content', async () => {
      const result = await claudeMock.extractEntities(
        'John Doe is the CEO of Acme Corporation based in New York.'
      );
      
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(3);
      
      // Check person entity
      const person = result.entities.find(e => e.type === EntityType.PERSON);
      expect(person).toBeDefined();
      expect(person?.name).toBe('John Doe');
      
      // Check organization entity
      const org = result.entities.find(e => e.type === EntityType.ORGANIZATION);
      expect(org).toBeDefined();
      expect(org?.name).toBe('Acme Corporation');
      
      // Check location entity
      const location = result.entities.find(e => e.type === EntityType.LOCATION);
      expect(location).toBeDefined();
      expect(location?.name).toBe('New York');
    });
    
    it('should apply confidence threshold when specified', async () => {
      const result = await claudeMock.extractEntities(
        'John Doe is the CEO of Acme Corporation based in New York.',
        { confidenceThreshold: 0.8 }
      );
      
      expect(result.success).toBe(true);
      // Should only include entities with relevance >= 0.8
      expect(result.entities).toHaveLength(2);
      
      const entityNames = result.entities.map(e => e.name);
      expect(entityNames).toContain('John Doe');
      expect(entityNames).toContain('Acme Corporation');
      expect(entityNames).not.toContain('New York');
    });
    
    it('should handle extraction errors gracefully', async () => {
      const result = await claudeMock.extractEntities(
        'This should trigger an error',
        { model: 'error' }
      );
      
      expect(result.success).toBe(false);
      expect(result.entities).toHaveLength(0);
      expect(result.error).toContain('Claude API error');
    });
    
    it('should extract meeting-related entities', async () => {
      const result = await claudeMock.extractEntities(
        'We have a Quarterly Review meeting where Jane Smith will present, scheduled for May 15, 2023 with the Marketing Department.'
      );
      
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(4);
      
      // Check event entity
      const event = result.entities.find(e => e.type === EntityType.EVENT);
      expect(event).toBeDefined();
      expect(event?.name).toBe('Quarterly Review');
      
      // Check date entity
      const date = result.entities.find(e => e.type === EntityType.DATE);
      expect(date).toBeDefined();
      expect(date?.name).toBe('2023-05-15');
    });
    
    it('should extract technical entities', async () => {
      const result = await claudeMock.extractEntities(
        'The project is using Machine Learning algorithms implemented in TensorFlow as described by Smith et al., published on November 1, 2022.'
      );
      
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(4);
      
      // Check technology entities
      const technologies = result.entities.filter(e => e.type === EntityType.TECHNOLOGY);
      expect(technologies).toHaveLength(2);
      expect(technologies[0].name).toBe('Machine Learning');
      expect(technologies[1].name).toBe('TensorFlow');
    });
  });
});