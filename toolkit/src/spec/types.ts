export interface Section {
  heading: string;
  startLine: number;
  endLine: number;
}

export interface IngestedDoc {
  path: string;
  type: string; // md | txt | pdf | docx | image | unknown | missing
  text: string;
  pages: number | null;
  sections: Section[];
  ocrConfidence: number | null;
  status: 'extracted' | 'needs_review';
  sensitivity: string[];
  note?: string;
}

export interface RequirementSource {
  doc: string;
  page: number | null;
  line: number | null;
  anchor: string | null;
}

export interface Requirement {
  id: string;
  text: string;
  type: 'functional' | 'nonfunctional' | 'constraint' | 'assumption';
  priority: 'must' | 'should' | 'could' | 'wont';
  source: RequirementSource;
  tags: string[];
  risk: string[];
  sensitivity: string[];
  status: 'extracted' | 'needs_review';
}

export interface RequirementsDoc {
  version: string;
  generatedAt: string;
  documents: string[];
  requirements: Requirement[];
}
