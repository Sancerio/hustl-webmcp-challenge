const emptySchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{},
  'additionalProperties': false,
};

const openSurfaceSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'surface': {
      'type': 'string',
      'enum': ['train', 'recovery', 'nutrition', 'coach', 'templates'],
    },
  },
  'required': ['surface'],
  'additionalProperties': false,
};

const workoutHistorySchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 10},
    'cursor': {'type': 'string', 'minLength': 1, 'maxLength': 128},
  },
  'additionalProperties': false,
};

const exerciseHistorySchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 10},
    'sinceDays': {
      'type': 'integer',
      'minimum': 1,
      'maximum': 3650,
      'default': 365,
    },
  },
  'additionalProperties': false,
};

const coachingTrendsSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'windowDays': {
      'type': 'integer',
      'enum': [7, 30, 90],
      'default': 30,
    },
  },
  'additionalProperties': false,
};

const nutritionProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'caloriesTarget': {'type': 'integer', 'minimum': 800, 'maximum': 6000},
    'proteinTarget': {'type': 'number', 'minimum': 0, 'maximum': 500},
    'carbsTarget': {'type': 'number', 'minimum': 0, 'maximum': 1500},
    'fatTarget': {'type': 'number', 'minimum': 0, 'maximum': 400},
    'rationale': {'type': 'string', 'minLength': 1, 'maxLength': 500},
  },
  'required': ['caloriesTarget', 'proteinTarget', 'carbsTarget', 'fatTarget'],
  'additionalProperties': false,
};

const foodProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'date': {'type': 'string', 'pattern': r'^\d{4}-\d{2}-\d{2}$'},
        'items': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 20,
          'items': {
            'type': 'object',
            'properties': {
              'foodName': {'type': 'string', 'minLength': 1, 'maxLength': 200},
              'servingGrams': {
                'type': 'number',
                'exclusiveMinimum': 0,
                'maximum': 5000,
              },
              'calories': {'type': 'number', 'minimum': 0, 'maximum': 5000},
              'proteinGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'carbsGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'fatGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'fiberGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'sugarGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'sodiumMg': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            },
            'required': [
              'foodName',
              'servingGrams',
              'calories',
              'proteinGrams',
              'carbsGrams',
              'fatGrams',
            ],
            'additionalProperties': false,
          },
        },
        'note': {'type': 'string', 'minLength': 1, 'maxLength': 500},
      },
      'required': ['date', 'items'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const foodLogEntriesSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'date': {
      'type': 'string',
      'pattern': r'^\d{4}-\d{2}-\d{2}$',
      'description': 'Synthetic local diary date in YYYY-MM-DD form.',
    },
  },
  'required': ['date'],
  'additionalProperties': false,
};

const foodLogRevisionChangesSchema = <String, Object?>{
  'type': 'object',
  'minProperties': 1,
  'properties': {
    'foodName': {'type': 'string', 'minLength': 1, 'maxLength': 200},
    'servingGrams': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 5000},
    'calories': {'type': 'number', 'minimum': 0, 'maximum': 5000},
    'proteinGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'carbsGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'fatGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'fiberGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'sugarGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'sodiumMg': {'type': 'number', 'minimum': 0, 'maximum': 100000},
  },
  'additionalProperties': false,
};

const foodLogEditProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'targetEntryId': {
          'type': 'string',
          'format': 'uuid',
          'description':
              'Opaque synthetic entry id returned by hustl_get_food_log_entries.',
        },
        'changes': foodLogRevisionChangesSchema,
      },
      'required': ['targetEntryId', 'changes'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const foodLogDeleteProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'targetEntryId': {
          'type': 'string',
          'format': 'uuid',
          'description':
              'Opaque synthetic entry id returned by hustl_get_food_log_entries.',
        },
      },
      'required': ['targetEntryId'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const templateExerciseSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'exerciseId': {'type': 'string', 'minLength': 1, 'maxLength': 120},
    'slug': {
      'type': 'string',
      'minLength': 1,
      'maxLength': 120,
      'pattern': r'^[a-z0-9-]+$',
    },
    'sets': {'type': 'integer', 'minimum': 1, 'maximum': 20},
    'repsTarget': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    'restTimerSeconds': {'type': 'integer', 'minimum': 0, 'maximum': 600},
    'weightTarget': {'type': 'number', 'minimum': 0, 'maximum': 2000},
    'rpeTarget': {'type': 'integer', 'minimum': 1, 'maximum': 10},
    'notes': {'type': 'string', 'minLength': 1, 'maxLength': 500},
  },
  'required': ['exerciseId', 'sets', 'restTimerSeconds'],
  'additionalProperties': false,
};

const templatePlanSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
    'description': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
    'exercises': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 30,
      'items': templateExerciseSchema,
    },
  },
  'required': ['name', 'exercises'],
  'additionalProperties': false,
};

const templateProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {'plan': templatePlanSchema},
  'required': ['plan'],
  'additionalProperties': false,
};

const templateEditSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'plan': templatePlanSchema,
    'baseUpdatedAt': {
      'type': 'string',
      'format': 'date-time',
      'minLength': 20,
      'maxLength': 40,
    },
  },
  'required': ['plan', 'baseUpdatedAt'],
  'additionalProperties': false,
};

const openProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'proposalId': {'type': 'string', 'minLength': 1, 'maxLength': 128},
  },
  'required': ['proposalId'],
  'additionalProperties': false,
};
