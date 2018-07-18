RSpec.describe K8s::Resource do
  include FixtureHelpers

  context "for a simple service resource" do
    subject { described_class.from_file(fixture_path('resources/service.yaml')) }

    it "loads the correct attributes" do
      expect(subject.apiVersion).to eq 'v1'
      expect(subject.kind).to eq 'Service'
      expect(subject.metadata.namespace).to eq 'default'
      expect(subject.metadata.name).to eq 'whoami'
      expect(subject.metadata.labels['app']).to eq 'whoami'
      expect(subject.spec.selector.to_hash).to eq({ :app => 'whoami' })
      expect(subject.spec.ports).to match Array
      expect(subject.spec.ports.first.port).to eq 80
      expect(subject.spec.ports.first.protocol).to eq 'TCP'
      expect(subject.spec.ports.first.targetPort).to eq 8000
    end

    describe "#to_json" do
      it "returns the correct JSON for the kube API" do
        expect(JSON.parse(subject.to_json)).to eq({
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'namespace' => 'default',
            'name' => 'whoami',
            'labels' => { 'app' => 'whoami' },
          },
          'spec' => {
            'selector' => { 'app' => 'whoami' },
            'ports' => [
              { 'port' => 80, 'protocol' => 'TCP', 'targetPort' => 8000 },
            ],
          },
        })
      end
    end

    describe '#merge' do
      it "returns a new copy with deep-merged attributes" do
        clone = subject.merge({metadata: { name: 'whoami2' }})

        expect(subject.metadata.name).to eq 'whoami'
        expect(clone.metadata.name).to eq 'whoami2'
      end

      it "merges label hashes" do
        clone = subject.merge({metadata: { labels: { 'test' => 'true' } }})

        expect(clone.metadata.labels.to_hash).to eq({
          :app => 'whoami',
          :test => 'true',
        })
      end

      it "merges with a modified copy" do
        other = described_class.from_file(fixture_path('resources/service_modified.yaml'))
        clone = subject.merge(other.to_hash)

        expect(clone.to_hash).to eq(
          apiVersion: 'v1',
          kind: 'Service',
          metadata: {
            namespace: 'default',
            name: 'whoami2',
            labels: { app: 'whoami', app2: 'whoami2' },
          },
          spec: {
            selector: { app: 'whoami', app2: 'whoami2' }, # XXX: orly
            ports: [
              { port: 80, protocol: 'TCP', targetPort: 8001 },
            ]
          },
        )
      end

      it "merges array object" do
        clone = subject.merge(
          spec: {
            ports: [
              { port: 80, protocol: 'TCP', targetPort: 8001 },
            ],
          }
        )

        expect(clone.to_hash[:spec][:ports]).to eq [
          { port: 80, protocol: 'TCP', targetPort: 8001 },
        ]
      end
    end

    describe "#==" do
      it "compares equal to itself" do
        expect(subject == subject).to be_truthy
      end

      it "compares equal to a JSON-roundtripped copy of the same resource" do
        expect(subject == described_class.from_json(JSON.parse(subject.to_json))).to be_truthy
      end

      it "does not compare equal to a merged copy" do
        expect(subject != subject.merge(metadata: { name: 'whoami2' })).to be_truthy
      end

      it "compares equal to an identical merged copy" do
        expect(subject == subject.merge(metadata: { name: 'whoami' })).to be_truthy
        expect(subject != subject.merge(metadata: { name: 'whoami' })).to be_falsey
      end
    end
  end
end
