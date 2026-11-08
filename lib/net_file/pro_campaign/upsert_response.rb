# frozen_string_literal: true

module NetFile
  module ProCampaign
    # The result of an upsert. NetFile returns 200 even when items fail, and
    # with rollbackOnAnyFailure false it reports "committed" when only some
    # items were written, so success? also requires that no item failed.
    UpsertResponse = Data.define(:url, :status, :request, :response) do
      def success?
        status == 200 && response["committed"] == true && response["failureCount"] == 0
      end

      def items
        response["items"]
      end
    end
  end
end
